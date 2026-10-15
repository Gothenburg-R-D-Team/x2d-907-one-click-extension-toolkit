/* Adapted from Radium Wang's X2D 4.2.0 audio_preview.c (MIT, 2026).
 * See licenses/radium-wang-shutter-MIT.txt and 快门音方案对比.md.
 * One owned child plays one validated private WAV through stock libaudioclient.
 * No camera-gui injection, network listener, global volume setter or idle stream.
 */
typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ssize_t;
extern int open(const char *,int,...),close(int),memcmp(const void *,const void *,size_t);
extern ssize_t read(int,void *,size_t);
extern ssize_t write(int,const void *,size_t);
extern int usleep(unsigned),sscanf(const char *,const char *,...);
struct audio_time {long sec,nsec;};extern int clock_gettime(int,struct audio_time *);
extern void *malloc(size_t),*memcpy(void *,const void *,size_t),*memset(void *,int,size_t);
extern void free(void *);
extern char *getenv(const char *);
extern int strcmp(const char *,const char *);
extern void _exit(int);
extern unsigned alarm(unsigned);
extern void (*signal(int,void (*)(int)))(int);
static volatile int interrupted;
static void interrupt_playback(int ignored){(void)ignored;interrupted=1;}
struct stream_handle { unsigned id,bytes;void *buffer; };
struct audio_frame { void *buffer;unsigned bytes,valid;unsigned char reserved[56]; };
_Static_assert(sizeof(struct stream_handle)==16,"X2D 4.2.0 stream ABI");
_Static_assert(sizeof(struct audio_frame)==72,"X2D 4.2.0 frame ABI");
extern int audio_client_get_dev_volume(const char *,unsigned *);
extern int audio_client_player_open_dev(const char *,const void *,int *);
extern int audio_client_player_close_dev(int);
extern int audio_client_player_open_stream(int,unsigned *,struct stream_handle *);
extern int audio_client_player_close_stream(int,struct stream_handle *);
extern int audio_client_player_write_frame(int,struct audio_frame *);
static unsigned u16(const unsigned char *p){return p[0]|((unsigned)p[1]<<8);}
static unsigned u32(const unsigned char *p){return u16(p)|(u16(p+2)<<16);}
static int read_all(int fd,unsigned char *p,unsigned bytes){
    while(bytes){ssize_t n=read(fd,p,bytes);if(n<=0)return 1;p+=n;bytes-=(unsigned)n;}return 0;
}
static int read_samples(unsigned char **output,unsigned *length){
    unsigned char header[44],extra;
    unsigned char *samples=0;
    int fd=open("/tmp/x2d-shutter-sound/playback.wav",0x8000 /* ARM64 O_NOFOLLOW */);
    if(fd<0)return 10;
    int error=11;
    if(read_all(fd,header,44))goto input_done;
    if(memcmp(header,"RIFF",4)||memcmp(header+8,"WAVEfmt ",8)||memcmp(header+36,"data",4))goto input_done;
    unsigned bytes=u32(header+40);
    /* 80--1500 ms authored sound; accept legacy files with a 150 ms tail. */
    if(u32(header+16)!=16||u16(header+20)!=1||u16(header+22)!=2||u32(header+24)!=48000||
       u32(header+28)!=192000||u16(header+32)!=4||u16(header+34)!=16||
       bytes<15360||bytes>316800||bytes%4||u32(header+4)!=bytes+36)goto input_done;
    samples=malloc(bytes);if(!samples){error=12;goto input_done;}
    if(read_all(fd,samples,bytes)||read(fd,&extra,1)!=0)goto input_done;
    error=0;
input_done:
    close(fd);
    if(error){free(samples);return error;}
    *output=samples;*length=bytes;return 0;
}
int x2d_play_once(void){
    unsigned char *samples=0;unsigned bytes=0;
    int error=read_samples(&samples,&bytes);if(error)return error;
    /* Stream gain 100 preserves source amplitude; device volume stays untouched. */
    unsigned volume[3]={0};
    if(audio_client_get_dev_volume("speaker",volume)<0||volume[0]>100||volume[1]>100||volume[0]!=volume[1]){
        free(samples);return 13;
    }
    int player=-1;
    struct stream_handle stream={0};
    unsigned config[11]={48000,16,2,0,2,0,100,0,0,0,0};
    if(audio_client_player_open_dev("speaker",0,&player)<0){free(samples);return 14;}
    if(audio_client_player_open_stream(player,config,&stream)<0){
        audio_client_player_close_dev(player);free(samples);return 15;
    }
    error=0;
    if(!stream.buffer||!stream.bytes||stream.bytes>1048576||stream.bytes%4)error=16;
    for(unsigned pos=0;!error&&!interrupted&&pos<bytes;){
        unsigned n=bytes-pos;if(n>stream.bytes)n=stream.bytes;
        struct audio_frame frame={0};
        frame.buffer=stream.buffer;frame.bytes=stream.bytes;frame.valid=stream.bytes;
        if(n<stream.bytes)memset(stream.buffer,0,stream.bytes);
        memcpy(stream.buffer,samples+pos,n);
        if(audio_client_player_write_frame(player,&frame)<0&&!interrupted)error=17;
        pos+=n;
    }
    if(audio_client_player_close_stream(player,&stream)<0&&!error)error=18;
    if(audio_client_player_close_dev(player)<0&&!error)error=19;
    free(samples);return error;
}
static unsigned long long realtime_ms(void){struct audio_time now;if(clock_gettime(0,&now))return 0;return (unsigned long long)now.sec*1000+(unsigned long long)now.nsec/1000000;}
static int control(char *token,int *play){
    char input[128]={0},action[5]={0},extra[2]={0};unsigned long long expires=0;
    int fd=open("/tmp/x2d-shutter-sound/play.request",0x8000);if(fd<0)return 0;
    ssize_t size=read(fd,input,sizeof(input)-1);close(fd);
    if(size<=0 || size>=127 || input[size-1]!='\n')return 0;
    int fields=sscanf(input,"XSP1 %40[0-9-] %4s %llu END %1s",token,action,&expires,extra);
    if(fields!=3)return 0;
    if(!strcmp(action,"STOP")){*play=0;return 1;}
    if(strcmp(action,"PLAY") || expires<realtime_ms())return 0;
    *play=1;return 1;
}
static void bound_call(void){alarm(3);}
static int close_voice(int *player,struct stream_handle *stream,int *opened){
    int error=0;if(*player<0)return 0;
    bound_call();if(*opened && audio_client_player_close_stream(*player,stream)<0)error=18;
    bound_call();if(audio_client_player_close_dev(*player)<0&&!error)error=19;
    alarm(0);*player=-1;*opened=0;memset(stream,0,sizeof(*stream));return error;
}
int x2d_play_persistent(void){
    unsigned char *samples=0;unsigned bytes=0;int error=read_samples(&samples,&bytes);if(error)return error;
    alarm(0); /* Never leave the one-shot startup alarm armed during idle. */
    int player=-1,playing=0,opened=0;unsigned pos=0;struct stream_handle stream={0};char previous[41]={0};
    while(!interrupted){
        char token[41]={0};int requested=0;
        if(control(token,&requested) && strcmp(previous,token)){
            memcpy(previous,token,sizeof(previous));playing=requested;pos=0;
            (void)write(1,requested?"XS_AUDIO_PLAY\n":"XS_AUDIO_STOP\n",14);
            if(!requested){error=close_voice(&player,&stream,&opened);if(error)break;}
        }
        if(!playing){usleep(10000);continue;}
        if(player<0){
            unsigned volume[3]={0},config[11]={48000,16,2,0,2,0,100,0,0,0,0};
            bound_call();if(audio_client_get_dev_volume("speaker",volume)<0||volume[0]>100||volume[1]>100||volume[0]!=volume[1]){error=13;break;}
            bound_call();if(audio_client_player_open_dev("speaker",0,&player)<0){error=14;break;}
            bound_call();if(audio_client_player_open_stream(player,config,&stream)<0){error=15;break;}
            opened=1;
            if(!stream.buffer||!stream.bytes||stream.bytes>1048576||stream.bytes%4){error=16;break;}
        }
        unsigned n=bytes-pos;if(n>stream.bytes)n=stream.bytes;
        struct audio_frame frame={0};frame.buffer=stream.buffer;frame.bytes=stream.bytes;frame.valid=stream.bytes;
        if(n<stream.bytes)memset(stream.buffer,0,stream.bytes);
        memcpy(stream.buffer,samples+pos,n);bound_call();
        if(audio_client_player_write_frame(player,&frame)<0){error=17;break;}
        alarm(0);pos+=n;
        if(pos>=bytes){playing=0;error=close_voice(&player,&stream,&opened);if(error)break;}
    }
    int closed=close_voice(&player,&stream,&opened);if(!error)error=closed;
    alarm(0);free(samples);return error;
}
#ifndef X2D_HOST_TEST
__attribute__((constructor)) static void start(void){
    const char *flag=getenv("X2D_SHUTTER_AUDIO_CHILD");
    if(!flag||strcmp(flag,"1"))return;
    signal(13,(void (*)(int))1); /* SIGPIPE */
    signal(10,interrupt_playback); /* SIGUSR1: new frame replaces the old tail. */
    signal(15,interrupt_playback); /* Owned shutdown only. */
    alarm(3); /* Bound a stuck client; stock binder cleans up the dead client. */
    (void)write(1,"XS_AUDIO_START\n",15);
    const char *persistent=getenv("X2D_SHUTTER_AUDIO_PERSIST");
    int result=persistent&&!strcmp(persistent,"1")?x2d_play_persistent():x2d_play_once();
    char code[19]="XS_AUDIO_EXIT_00\n";
    code[14]=(char)('0'+result/10);code[15]=(char)('0'+result%10);
    (void)write(1,code,17);
    _exit(result);
}
#endif
