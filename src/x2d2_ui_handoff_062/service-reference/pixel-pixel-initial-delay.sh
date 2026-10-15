#!/system/bin/sh
# X2D 4.2.0 / 24849 only. Change the initial MultiShot delay in process RAM.
# No capture method, persistent file or GUI permission changes.
# A failed rollback never resumes damaged instructions; init may reload the service.
root=${X2D_PIXEL_RAM_ROOT:-/tmp/x2d-native-multishot}
proc=/proc
if [ "${X2D_PIXEL_OFFLINE_TEST:-}" = 1 ]; then proc=${X2D_PIXEL_PROC_ROOT:?}; fi
stock=341590ef34dd99dfae33c4efa4ecb1bb7c2be6aceacd7bf29c6c0eaca1fe6175
stock_hook=c0000036
owned_hook=79050014
idle() {
    status=$(timeout 3 dbus-send --system --print-reply --dest=com.hasselblad.camera /camera \
        org.freedesktop.DBus.Properties.Get string:com.hasselblad.camera string:exposure_status |
        awk '/variant[[:space:]]+int32[[:space:]]/{print $NF}')
    case "$status" in ''|*[!0-9]*) return 1;; esac
    [ "$((status & 1299))" -eq 0 ]
}
parse_target() {
    IFS='|' read -r service address stamp extra <"$root/initial-delay.target" || return 1
    [ -z "$extra" ] || return 1
    for n in "$service" "$address" "$stamp"; do case "$n" in ''|*[!0-9]*) return 1;; esac; done
    case "$address" in 0|00*) return 1;; esac
}
load_target() {
    parse_target && [ "$(awk '{print $22}' "$proc/$service/stat" 2>/dev/null)" = "$stamp" ]
}
read_memory() {
    hook_address=$(awk -v a="$address" 'BEGIN {printf "%.0f\n",a-5604}')
    current=$(busybox dd if="$proc/$service/mem" bs=1 skip="$address" count=164 2>/dev/null | sha256sum | cut -d' ' -f1)
    current_hook=$(od -An -tx1 -N4 -j "$hook_address" "$proc/$service/mem" | tr -d ' \n')
    if [ "$current" = "$stock" ] && [ "$current_hook" = "$stock_hook" ];then current_ms=stock;return 0;fi
    [ "$current_hook" = "$owned_hook" ] || return 1
    case "$current" in
        ef3a665f303d700d374df0a70739737bcf547717a95aba2b0041052a428c5eeb) current_ms=0;;
        d6c32fa535b3d1335f8e141b724a27c8ff9ee67209730a4b97dd211d8453860c) current_ms=2000;;
        7ce7ca54a46cfec5bef8ab734528c9696d55d8c6ac86ca37a2bdc9565f08fe6c) current_ms=3000;;
        8c5e95ecd2ff12ec607adfd176a304944b9b45cb70d0ca2b456f3aa4fab1bdb5) current_ms=4000;;
        f3e50f1731320de690fe87ddef39ad6b639a40475b2df5cf33a17c2b566acba4) current_ms=5000;;
        c11161d02927ae5be8bd8a108e8171d2df508fa4bc311558acb942ec3dd771c9) current_ms=6000;;
        368a09ec4c182391c24513d63abe98505b64864bb13bafd590821d97740143bb) current_ms=7000;;
        a183ff8cdb0fb0a8c4785b265f8baae1bce4f7f23a96a1db3a816e14419bec53) current_ms=8000;;
        6a286fe9f251bc8f85ffd955e9df1abf2ff4847a761d0db09d60d88cef6905f1) current_ms=9000;;
        88a687a43349cdfbe6b446e2c9dec8877a18c26a170d8c5cfd448d97da076d05) current_ms=10000;;
        3009a1800f5121ef2429190103497a24a74e9103db03fccbbc0778b6ffb4125f) current_ms=11000;;
        3843c9810a437dffb451044c19e5c120a4aa1641d80c97e24aca89c99423d97a) current_ms=12000;;
        8d7437d3bd8d4cf9409d4192846acff66961d74fc82a2e4ec2259898d10ac87a) current_ms=13000;;
        8ead4e8a91fe1c5c4c25b9a02cfa3e1a71f4535b832ee2d7e5f473b9051466f1) current_ms=14000;;
        1e9b3bfdced01d4f2b3ffd9c83a9bac042cbd7d5b0d6c5d1a4e584748e36c30a) current_ms=15000;;
        ef5107a9a6e88eaf36923b10491f4ce83c5cb80c0c05edffbc3b1b17c3d9bf6d) current_ms=16000;;
        3aef0095cda62703f45b93035ca041b752062670ed9e5e90103c4ca426a61ab2) current_ms=17000;;
        c6c2321657648071931a8ef1b9d670f22c6b192b56cde13cd14edc355be4af62) current_ms=18000;;
        91396cdbd5559957eab26cfe6426a79505ddd0aa4ab9c17c2396198e4a67a49b) current_ms=19000;;
        406c2e28d5561eda506fbe7eeea15efb1a9963c3ab79afacd6e48ccbb73bfeec) current_ms=20000;;
        5c1aa8b8085bedcaeea1c45d980b0d0a6a419cc108368ad7cc6da411dfb1bb02) current_ms=21000;;
        10930d2fd417ed91c2651e2e7dd163f0f892da155141be3d0529995ad650f0ba) current_ms=22000;;
        67d85aa78daa50f839e6f9d66cd108bd58bf499563bd95181f70f0c0292f7a46) current_ms=23000;;
        079252dee4d65786277d12402a0c42c33c41cc918e08c81bd6dceea4d7493c69) current_ms=24000;;
        3c507b278b64204a91cd0a1a8f8f53ef23d61c119b1aba515bef8900afb47ccb) current_ms=25000;;
        ee6fd120b54767121d8c4480c6b0ce7ce21661fd354bfb987da0e45ce88efafd) current_ms=26000;;
        a29998486d5d6970d08c666b6d591ea2ff67c8007b2e660ce321dd4f73651270) current_ms=27000;;
        d829fb920b578b405477de2d54b58cc3de7f34c7d011fe7a41f732b09fb9e764) current_ms=28000;;
        52f560e3958dee71d4214099de3e3d7dcd02d7b08bf18781e1435a43069ef88e) current_ms=29000;;
        27cb6073dd7e3c6dd7fba0a91cc3056973748af09efbd78e754c818f481c7fb6) current_ms=30000;;
        a288acf7d116f3b9175add17c671de597f503c563731a32ea38a88366f72fa42) current_ms=31000;;
        b045c0730f70148d1db390d2028b24879f07b3df71771b57f488841fb653b247) current_ms=32000;;
        acc1e5f189050801cfde1971f53ac0ae4e5f15a51357cde2ab32a2085629ab78) current_ms=33000;;
        83cab6173a5b33ac39f5c2d2ce5c8459cfcced5ff3a6a09f26e2910386c9f555) current_ms=34000;;
        fdbf246dda454e7786692b78327dbeaf273dfd38d93ee8c17473c45e20d08f31) current_ms=35000;;
        7771f07e1d9ecd966c52418030e5f4f887cc4cffccbcd49e848408ba06dba78c) current_ms=36000;;
        4517079081ce6d64c3fc4be107419e24da61d3ffc7516f35b34a8634385e502c) current_ms=37000;;
        0f7b086ce084816b729547af0000c23badb766a83de8f604305eefe5daec69c1) current_ms=38000;;
        b746f1cda812ccf0092d4ad12ae80cf0c0cf9de3a24e3c661cac07f9ab99ddad) current_ms=39000;;
        726fb5808e2d06d61a38012802506048f04eedb47730e0d6b9f9f9e07bc03d65) current_ms=40000;;
        51ae05f17f51c9ff92b878a07ba49cb2970e1cd7c7e8fd10a74b76ff7f2811f4) current_ms=41000;;
        f4c0291591aa186aa4b4ee86fb21b3917c53b4b9366e8f64d20eca648077def7) current_ms=42000;;
        d93cfde096edcda484e7718363f727da2de51547440c6dce67d8e8f89df0ef57) current_ms=43000;;
        60ab65413185512473d83ed50856f437238543cec94b6610078cfb63198f69bb) current_ms=44000;;
        2945fd892cc3ac32ea6c4e54e62d38e3fd526276b876af1d3f8b7d3a3f45034b) current_ms=45000;;
        78d707c888431bb7bb52ce10246c201b52e4ded9fde88b44a303b15aab99adcb) current_ms=46000;;
        70d00c5f8accf325e90d14a5dbf4f9a40b7603164ce5844eec8469c091ed79d8) current_ms=47000;;
        67c5009bd4b39661e0ae34bb9b1cbb0177e8e663ede3097c86afb35cb67b24af) current_ms=48000;;
        b1583fe2851f4d8e4a7cd284301f7d76b1645a8a8f1ffb717e2cc894dfab9a91) current_ms=49000;;
        211acc02dd507c280aee06d48dad665d843df0bfe5c3d323fc638075e1d64445) current_ms=50000;;
        fd78628fb9e747d4b3305af0f6b6d1e7c02e70c803226af649b8c8b7d760c260) current_ms=51000;;
        73e8837351358847bef411f6b1d6717914de7881d71612020f6244fe610910a0) current_ms=52000;;
        f7c2bb74c0fd95d54d90753d715591810a425390987db7fc7f245ae1537109cc) current_ms=53000;;
        9cd6a270d871f2150ee878b59b0fa5b7e8d96553d3754d723283c224803bb564) current_ms=54000;;
        9a9f9ee2773379dd26bcd3f1e4e9d7d35ac86bfc04136800690979ba932564b4) current_ms=55000;;
        28fdc97529e14f87fbebfefb52f2b4d246ada8a74d489c87a2081a063c013e17) current_ms=56000;;
        376c2f2088f82e8d57dcc9f3e6132a75ad635128794296efa3ad974f59654b26) current_ms=57000;;
        3993a9bb7990cb129ebcbf940e195b307f884d48a93d8f4d8ed3eaea23c8c0f2) current_ms=58000;;
        cb0c751e8b5fcbdce428a19e1fec277571215ce84c1b59caebd2312002d306d9) current_ms=59000;;
        899df9f957e167b15a0a6a47e022b25b41b8333375b870687ab35afb220fef83) current_ms=60000;;
        *) return 1;;
    esac
}
resume_target() {
    if [ "${X2D_PIXEL_OFFLINE_TEST:-}" != 1 ] && load_target; then kill -CONT "$service" 2>/dev/null; fi
}
finish_memory() {
    if [ "${dirty:-0}" = 1 ]; then rollback_memory; else resume_target; fi
}
stopped_clear() {
    count=0
    for task in "$proc/$service"/task/*; do
        [ -r "$task/status" ] && [ -r "$task/syscall" ] || return 1
        state=$(awk '$1=="State:"{print $2}' "$task/status")
        tracer=$(awk '$1=="TracerPid:"{print $2}' "$task/status")
        [ "$state" = T ] && [ "$tracer" = 0 ] || return 1
        pc=$(awk '{print $NF}' "$task/syscall")
        case "$pc" in 0x*) ;; *) return 1;; esac
        clear=$(awk -v pc="$pc" -v address="$address" 'BEGIN {
            digits="0123456789abcdef";n=0;hex=substr(pc,3)
            if(length(hex)==0) exit 1
            for(i=1;i<=length(hex);i++){v=index(digits,substr(hex,i,1))-1;if(v<0)exit 1;n=n*16+v}
            if(n==0 || (n>=address && n<address+164) || (n>=address-5604 && n<address-5600))exit 1
            print "clear"
        }') || return 1
        [ "$clear" = clear ] || return 1
        count=$((count+1)); [ "$count" -le 512 ] || return 1
    done
    [ "$count" -gt 0 ]
}
write_memory() {
    load_target && idle && read_memory || return 1
    printf %s "$payload" | base64 -d >"$root/initial-delay.bytes.new" || return 1
    if [ "$expected" = stock ];then hook_payload=wAAANg==;else hook_payload=eQUAFA==;fi
    printf %s "$hook_payload" | base64 -d >"$root/initial-delay.hook.new" || return 1
    [ "$(stat -c %s "$root/initial-delay.bytes.new")" = 164 ] && [ "$(stat -c %s "$root/initial-delay.hook.new")" = 4 ] || return 1
    dirty=0
    trap 'finish_memory; release_locks' EXIT
    trap 'finish_memory; release_locks; trap - EXIT; exit 1' HUP INT TERM
    if [ "${X2D_PIXEL_OFFLINE_TEST:-}" != 1 ];then kill -STOP "$service" || return 1;fi
    load_target && read_memory || { resume_target; return 1; }
    if [ "${X2D_PIXEL_OFFLINE_TEST:-}" != 1 ]; then
        attempts=0
        while ! stopped_clear; do
            attempts=$((attempts+1)); if [ "$attempts" -ge 100 ]; then resume_target;return 1;fi
            sleep .01
        done
    fi
    before=$current;before_hook=$current_hook
    busybox dd if="$proc/$service/mem" of="$root/initial-delay.before" bs=1 skip="$address" count=164 2>/dev/null || { resume_target;return 1; }
    busybox dd if="$proc/$service/mem" of="$root/initial-delay.hook.before" bs=1 skip="$hook_address" count=4 2>/dev/null || { resume_target;return 1; }
    [ "$(stat -c %s "$root/initial-delay.before")" = 164 ] && [ "$(stat -c %s "$root/initial-delay.hook.before")" = 4 ] || { resume_target;return 1; }
    dirty=1
    if [ "$expected" = stock ];then
        busybox dd if="$root/initial-delay.hook.new" of="$proc/$service/mem" bs=1 seek="$hook_address" conv=notrunc 2>/dev/null || { rollback_memory;return 1; }
    fi
    busybox dd if="$root/initial-delay.bytes.new" of="$proc/$service/mem" bs=1 seek="$address" conv=notrunc 2>/dev/null || { rollback_memory;return 1; }
    if [ "$expected" != stock ];then
        busybox dd if="$root/initial-delay.hook.new" of="$proc/$service/mem" bs=1 seek="$hook_address" conv=notrunc 2>/dev/null || { rollback_memory;return 1; }
    fi
    read_memory && [ "$current_ms" = "$expected" ] || { rollback_memory;return 1; }
    dirty=0;resume_target
    (printf '%s\n' "$expected" >"$root/initial-delay.current.new" && mv "$root/initial-delay.current.new" "$root/initial-delay.current") || rm -f "$root/initial-delay.current.new"
    trap release_locks EXIT; trap 'exit 143' HUP INT TERM
}
rollback_memory() {
    n=0
    while [ "$n" -lt 3 ];do
        if busybox dd if="$root/initial-delay.hook.before" of="$proc/$service/mem" bs=1 seek="$hook_address" conv=notrunc 2>/dev/null &&
           busybox dd if="$root/initial-delay.before" of="$proc/$service/mem" bs=1 seek="$address" conv=notrunc 2>/dev/null &&
           read_memory && [ "$current" = "$before" ] && [ "$current_hook" = "$before_hook" ];then
            dirty=0;resume_target;return 0
        fi
        n=$((n+1))
    done
    if [ "${X2D_PIXEL_OFFLINE_TEST:-}" != 1 ];then kill -KILL "$service";fi
    printf '%s\n' RAM_ROLLBACK_FAILED >"$root/initial-delay.fault"
    dirty=0;return 1
}
case "$1" in prepare|set|restore)
    mkdir -p /tmp/x2d-speed-buff
    count=0
    while ! mkdir /tmp/x2d-speed-buff/aft-lock 2>/dev/null; do count=$((count+1)); [ "$count" -lt 100 ] || exit 36; sleep .1; done
    count=0
    while ! mkdir /tmp/x2d-speed-buff/lock 2>/dev/null; do
        count=$((count+1)); if [ "$count" -ge 100 ]; then rmdir /tmp/x2d-speed-buff/aft-lock; exit 36; fi; sleep .1
    done
    release_locks() { rmdir /tmp/x2d-speed-buff/lock /tmp/x2d-speed-buff/aft-lock; }
    trap release_locks EXIT
    trap 'exit 143' HUP INT TERM
    ;; esac
case "$1" in
    prepare)
        idle || exit 30
        [ "$(sha256sum /system/bin/camera-service | cut -d' ' -f1)" = fbcf828f73bca13f0c8b95e7dd0b95ac483ae36954ec06179098c8a1a65f9f82 ] || exit 31
        service=$(pidof camera-service)
        case "$service" in ''|*[!0-9]*) exit 32;; esac
        base=$(awk '$2=="r-xp" && $3=="00000000" && $NF=="/system/bin/camera-service" {print $1}' "$proc/$service/maps")
        base=${base%%-*}; case "$base" in ''|*[!0-9a-f]*) exit 33;; esac
        # Android mksh arithmetic is 32-bit even on this ARM64 camera.
        # awk's exact integer range covers all mapped userspace addresses.
        address=$(awk -v hex="$base" 'BEGIN {
            n=0; digits="0123456789abcdef"
            for(i=1;i<=length(hex);i++) n=n*16+index(digits,substr(hex,i,1))-1
            printf "%.0f\n",n+1287544
        }')
        stamp=$(awk '{print $22}' "$proc/$service/stat")
        printf '%s|%s|%s\n' "$service" "$address" "$stamp" >"$root/initial-delay.target.new"
        mv "$root/initial-delay.target.new" "$root/initial-delay.target" || exit 34
        load_target && read_memory && [ "$current_ms" = stock ] || exit 35
        payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FgCAUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=; expected=0
        write_memory || exit 36
        ;;
    read)
        load_target && read_memory && [ "$current_ms" != stock ] || exit 40
        printf '%s\n' "$current_ms"
        ;;
    set)
        case "$2" in
            0) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FgCAUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            2000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FvqAUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            3000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FneBUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            4000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FvSBUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            5000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FnGCUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            6000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fu6CUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            7000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FmuDUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            8000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FuiDUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            9000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FmWEUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            10000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FuKEUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            11000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fl+FUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            12000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FtyFUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            13000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FlmGUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            14000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FtaGUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            15000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FlOHUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            16000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FtCHUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            17000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fk2IUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            18000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FsqIUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            19000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FkeJUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            20000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FsSJUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            21000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FkGKUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            22000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fr6KUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            23000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FjuLUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            24000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FriLUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            25000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FjWMUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            26000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FrKMUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            27000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fi+NUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            28000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FqyNUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            29000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FimOUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            30000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FqaOUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            31000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FiOPUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            32000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FqCPUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            33000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fh2QUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            34000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FpqQUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            35000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FheRUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            36000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FpSRUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            37000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FhGSUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            38000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fo6SUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            39000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FguTUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            40000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FoiTUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            41000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FgWUUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            42000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FoKUUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            43000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fv+UUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            44000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FnyVUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            45000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FvmVUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            46000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FnaWUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            47000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FvOWUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            48000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FnCXUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            49000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fu2XUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            50000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FmqYUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            51000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FueYUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            52000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FmSZUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            53000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FuGZUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            54000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fl6aUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            55000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FtuaUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            56000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FlibUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            57000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FtWbUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            58000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FlKcUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            59000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1Fs+cUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            60000) payload=HxgAcWA1AFT/gwLR+F8GqfZXB6n0Twip/XsJqf1DApH3AwAq4AMUqiAhDJThAwCqADQAkABsRfl2OAeU9QMAqu4v/5dgAQA1FkydUjYBADRXAAA01iIDEdQKBJQBQDaL4AMVqo09/5c4AIBSAwAAFBYZgFL4AxcqgEIAkeEDFioCVwaU8QMYKv17San0T0ip9ldHqfhfRqn/gwKR0Uz/NGD6/xc=;;
            *) exit 41;;
        esac
        expected=$2
        load_target && read_memory && [ "$current_ms" != stock ] || exit 42
        write_memory || exit 43
        ;;
    restore)
        [ -f "$root/initial-delay.target" ] || exit 0
        parse_target || exit 44
        # A dead or reused PID has lost our RAM hook. Do not touch its successor.
        actual_stamp=$(awk '{print $22}' "$proc/$service/stat" 2>/dev/null)
        if [ "$actual_stamp" != "$stamp" ]; then
            rm -f "$root/initial-delay.target"
            exit 0
        fi
        payload=4AMTqikhDJQUNACQ4QMAqpRuRfngAxSqfjgHlOEDFjLiAwAygzv/l+ADE6ofIQyU4QMAquADFKp2OAeUAJBE+QgAQPkI0UH5AAE/1qAFADXgAxOqFSEMlOEDAKoANACQAGxF+Ws4B5TzAwCq4AscMi4m/Zf0AwCqQX2AUrW9AJTVIwCQtT41keEFgFIiDIBS4AMVqlEm/ZfgAAC0wCMAkAA8NZE=; expected=stock
        write_memory || exit 45
        ;;
    *) exit 46;;
esac
