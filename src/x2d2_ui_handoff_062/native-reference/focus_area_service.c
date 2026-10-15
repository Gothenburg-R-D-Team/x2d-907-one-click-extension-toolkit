/* X2D 4.2.0 temporary AF ROI extension. No disk patch and no motor commands.
 * Interposes existing APIs in the temporary camera-service process only. */
typedef __SIZE_TYPE__ size_t; typedef __PTRDIFF_TYPE__ ssize_t; typedef unsigned long long u64;
typedef unsigned int u32;
extern void *dlsym(void *,const char *),*memcpy(void *,const void *,size_t);
extern int socket(int,int,int),bind(int,const void *,unsigned),listen(int,int),accept(int,void *,void *),close(int),setsockopt(int,int,int,const void *,unsigned);
extern int open(const char *,int,...);
extern ssize_t read(int,void *,size_t),write(int,const void *,size_t);
extern ssize_t send(int,const void *,size_t,int);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *),pthread_detach(unsigned long);
extern int snprintf(char *,size_t,const char *,...),sscanf(const char *,const char *,...);
extern int strncmp(const char *,const char *,size_t),strcmp(const char *,const char *);
extern char *getenv(const char *),*strstr(const char *,const char *);
struct timespec { long sec,nsec; }; extern int clock_gettime(int,struct timespec *);
struct timeval { long sec,usec; };
struct address { unsigned short family,port; u32 address; unsigned char pad[8]; };
struct roi { u32 attribute; float x,y,w,h; u32 tail; };
_Static_assert(sizeof(struct roi)==24,"Pinned ROI layout");
typedef int (*fn0)(int); typedef int (*fnroi)(int,const struct roi *);
static fn0 real_run,real_manager,real_start,real_result;
static fnroi real_raw,real_hybrid;
static volatile u32 revision,mode,width,height,allow,retry,request_id;
static volatile u64 request_ms;
static volatile u32 ready,run_hits,roi_hits,applied_mode,applied_request,retry_ack,retry_ok,has_origin;
static struct roi origin,current;
static u32 consumed_retry,expanded,inside_retry,area_owned;
static const char *token;
static u64 ms(void) { struct timespec t; if(clock_gettime(1,&t))return 0; return (u64)t.sec*1000+(u64)t.nsec/1000000; }
static void *next(const char *n) { return dlsym((void *)-1,n); }
struct config { u32 mode,w,h,allow,retry,id; u64 when; };
static struct config snapshot(void) {
 struct config c={0}; u32 before=__atomic_load_n(&revision,__ATOMIC_ACQUIRE);
 if(before&1)return c;
 c.mode=mode;c.w=width;c.h=height;c.allow=allow;c.retry=retry;c.id=request_id;c.when=request_ms;
 if(before!=__atomic_load_n(&revision,__ATOMIC_ACQUIRE)||ms()-c.when>1000)c.allow=0;
 return c;
}
static int valid_roi(const struct roi *p) {
 return p && p->x>=0 && p->y>=0 && p->w>0 && p->h>0 && p->x+p->w<=1.001f && p->y+p->h<=1.001f;
}
static float bound(float v,float lo,float hi) { return v<lo?lo:v>hi?hi:v; }
static struct roi shape(struct roi p,struct config c) {
 float cx=p.x+p.w*.5f,cy=p.y+p.h*.5f;
 if(c.mode==2){p.w=c.w/10000.0f;p.h=c.h/10000.0f;}
 else if(c.mode==1 && expanded){p.w=bound(origin.w*3,0.04f,0.24f);p.h=bound(origin.h*3,0.04f,0.24f);}
 p.x=bound(cx-p.w*.5f,0,1-p.w);p.y=bound(cy-p.h*.5f,0,1-p.h);
 return p;
}
int af_set_raw_roi(int ch,const struct roi *p) {
 if(!real_raw)real_raw=(fnroi)next("af_set_raw_roi");
 if(ch==0 && valid_roi(p)){origin=*p;has_origin=1;}
 return real_raw?real_raw(ch,p):-1;
}
int hybrid_af_set_roi(int ch,const struct roi *p) {
 if(!real_hybrid)real_hybrid=(fnroi)next("hybrid_af_set_roi");
 struct config c=snapshot();struct roi r;
 if(ch==0 && ready && (c.allow&1) && c.mode && valid_roi(p)) {
  r=shape(*p,c);int result=real_hybrid?real_hybrid(ch,&r):-1;
  roi_hits++;if(result==0){
   if(applied_request!=c.id || applied_mode!=c.mode){char line[160];int n=snprintf(line,sizeof(line),"X2D_AREA_ROI_APPLIED id=%u mode=%u rect=%.4f,%.4f,%.4f,%.4f\n",c.id,c.mode,(double)r.x,(double)r.y,(double)r.w,(double)r.h);if(n>0 && n<(int)sizeof(line))(void)write(1,line,n);}
   current=r;applied_request=c.id;applied_mode=c.mode;area_owned=1;
  }
  return result;
 }
 return real_hybrid?real_hybrid(ch,p):-1;
}
int hybrid_af_start(int ch) {
 if(!real_start)real_start=(fn0)next("hybrid_af_start");
 if(ch==0 && !inside_retry){expanded=0;consumed_retry=retry;retry_ok=0;}
 return real_start?real_start(ch):-1;
}
int af_roi_manager_run(int ch) {
 if(!real_manager)real_manager=(fn0)next("af_roi_manager_run");
 struct config c=snapshot();
 if(ch==0 && ready && has_origin && real_raw && (((c.allow&1)&&c.mode)||area_owned)) {
  /* Run after the stock command manager, before its stock ROI manager.
   * A single rectangle; preserve attribute/tail and the manufacturer lifecycle. */
  struct roi r=((c.allow&1)&&c.mode)?shape(origin,c):origin;
  (void)real_raw(ch,&r);if(!(c.allow&1)||!c.mode)area_owned=0;
 }
 return real_manager?real_manager(ch):-1;
}
int dji_af_run(int ch) {
 if(!real_run)real_run=(fn0)next("dji_af_run");
 if(ch==0 && ready){
  run_hits++;struct config c=snapshot();
  if(!(c.allow&1)||c.mode!=1)expanded=0;
  if(c.mode==1 && (c.allow&2) && has_origin && c.retry && c.retry!=consumed_retry){
   consumed_retry=c.retry;retry_ack=c.retry;
   /* GUI sends exactly one request for the stock Failed result while AF-S
    * session is still active. A nonzero HAF result confirms it is terminal.
    * Never restart a running search, and never issue an exposure command. */
   if(!expanded && real_result && real_result(ch)!=0 && real_start){
    expanded=1;inside_retry=1;retry_ok=(real_start(ch)==0);inside_retry=0;
    char line[96];int n=snprintf(line,sizeof(line),"X2D_AREA_EXPAND_RETRY id=%u started=%u\n",c.id,retry_ok);if(n>0 && n<(int)sizeof(line))(void)write(1,line,n);
   }
  }
 }
 return real_run?real_run(ch):-1;
}
static void publish(u32 m,u32 w,u32 h,u32 a,u32 r,u32 id) {
 __atomic_add_fetch(&revision,1,__ATOMIC_ACQ_REL);
 mode=m;width=w;height=h;allow=a;retry=r;request_id=id;request_ms=ms();
 __atomic_add_fetch(&revision,1,__ATOMIC_RELEASE);
}
struct wait_fd {int fd;short events,revents;}; extern int poll(struct wait_fd *,unsigned long,int);
static void refresh_api(void){if(!real_run)real_run=(fn0)next("dji_af_run");if(!real_manager)real_manager=(fn0)next("af_roi_manager_run");if(!real_start)real_start=(fn0)next("hybrid_af_start");if(!real_result)real_result=(fn0)next("hybrid_af_get_result");if(!real_raw)real_raw=(fnroi)next("af_set_raw_roi");if(!real_hybrid)real_hybrid=(fnroi)next("hybrid_af_set_roi");ready=real_run&&real_manager&&real_start&&real_result&&real_raw&&real_hybrid;}
extern int mkdir(const char *,unsigned),openat(int,const char *,int,...);
static void *serve(void *unused) {
 (void)unused;int s=socket(2,1,0);if(s<0)return 0;
 int one=1;setsockopt(s,1,2,&one,sizeof(one));
 struct address address={2,0x3bdb,0x0100007f,{0}}; /* port 56123, loopback only */
 if(bind(s,&address,sizeof(address))||listen(s,4)){close(s);return 0;}
 unsigned last_ready=2;
 for(;;){refresh_api();
  if(last_ready!=ready){
   (void)mkdir("/tmp/x2d-focus-area",0700);
   int directory=open("/tmp/x2d-focus-area",0x4000|0x8000);
   int marker=directory>=0?openat(directory,"backend.ready",1|64|512|0x8000,0600):-1;
   if(directory>=0)close(directory);
   if(marker>=0){const char *value=ready?"READY\n":"API_MISSING\n";(void)write(marker,value,ready?6:12);close(marker);last_ready=ready;}
  }
  struct wait_fd pending={s,1,0};if(poll(&pending,1,250)<=0)continue;
  int fd=accept(s,0,0);if(fd<0)continue;
  struct timeval tv={1,0};setsockopt(fd,1,20,&tv,sizeof(tv));setsockopt(fd,1,21,&tv,sizeof(tv));
  char input[512]={0};ssize_t n=read(fd,input,sizeof(input)-1);
  u32 m,w,h,a,r,id;char supplied[65]={0};int accepted=0;
  if(n>0 && sscanf(input,"GET /state?token=%64[^&]&mode=%u&w=%u&h=%u&allow=%u&retry=%u&id=%u",supplied,&m,&w,&h,&a,&r,&id)==7 &&
     token && !strcmp(supplied,token) && m<=2 && w>=400 && w<=3500 && h>=400 && h<=3500 && w*h<=9000000 && a<=3){
   publish(m,w,h,a,r,id);accepted=1;
  }
  char body[512],reply[768];
  int length=snprintf(body,sizeof(body),"{\"ready\":%s,\"accepted\":%s,\"runHits\":%u,\"roiHits\":%u,\"origin\":%s,\"appliedMode\":%u,\"appliedId\":%u,\"retryAck\":%u,\"retryStarted\":%s,\"x\":%.5f,\"y\":%.5f,\"w\":%.5f,\"h\":%.5f}\n",ready?"true":"false",accepted?"true":"false",run_hits,roi_hits,has_origin?"true":"false",applied_mode,applied_request,retry_ack,retry_ok?"true":"false",(double)current.x,(double)current.y,(double)current.w,(double)current.h);
  int len=snprintf(reply,sizeof(reply),"HTTP/1.0 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n%s",accepted?"200 OK":"403 Forbidden",length,body);
  if(len>0 && len<(int)sizeof(reply)){ssize_t sent=0;while(sent<len){ssize_t q=send(fd,reply+sent,len-sent,0x4000);if(q<=0)break;sent+=q;}} /* MSG_NOSIGNAL */
  close(fd);
 }
}
__attribute__((constructor)) static void init(void) {
 const char *enable=getenv("X2D_FOCUS_AREAS");if(!enable||strcmp(enable,"1"))return;
 token=getenv("X2D_AREA_TOKEN");if(!token||!token[0])return;
 real_run=(fn0)next("dji_af_run");real_manager=(fn0)next("af_roi_manager_run");real_start=(fn0)next("hybrid_af_start");
 real_result=(fn0)next("hybrid_af_get_result");real_raw=(fnroi)next("af_set_raw_roi");real_hybrid=(fnroi)next("hybrid_af_set_roi");
 unsigned long thread;if(!pthread_create(&thread,0,serve,0))pthread_detach(thread);
}
