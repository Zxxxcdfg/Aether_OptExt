#!/system/bin/sh
# Aether OptExt — Magisk/KernelSU 安装脚本
# 安装时按 CPU 拓扑展开语义占位符，精确适配 1/2/3/4 层 SOC：
#   {e_core}   最低频层（能效小核）
#   {p1_core}  中核（第 2 层）
#   {p2_core}  大核（第 3 层，仅 4 层 SOC 存在）
#   {p_core}   p1 ∪ p2（全部中间层）
#   {hp_core}  最高频层（超大核）
#   {all_core} 全部 present CPU
# 拓扑命名惯例（大核在前）：1+3+4 = 超大核1 + 大核3 + 小核4
# 2 层 SOC：p1/p2 为空；3 层：p2 为空；1 层：e=hp=全部

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/aether-optext 0 0 0755

# 清除旧缓存
rm -f /sdcard/Android/Aether/threads_cache 2>/dev/null

TARGET="/sdcard/Android/Aether"
mkdir -p "$TARGET" 2>/dev/null

# 部署 asoul 兼容名单（主程序检测到 asoul 模块时读取）
if [ -f "$MODPATH/gamelist" ]; then
    cp "$MODPATH/gamelist" "$TARGET/gamelist" 2>/dev/null
fi

# 按 cpufreq 最高频分组检测 CPU 簇，输出 E_CORE/P1_CORE/P2_CORE/HP_CORE
# 输出统一压缩为 range 格式（如 0-5,6-7），避免列出每个核心
eval "$(for policy in /sys/devices/system/cpu/cpufreq/policy[0-9]*; do
    [ -d "$policy" ] || continue
    freq=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null)
    cpus=$(cat "$policy/related_cpus" 2>/dev/null)
    [ -z "$freq" ] || [ -z "$cpus" ] && continue
    echo "$freq:$cpus"
done | sort -t: -k1,1n | awk -F: '
    function normalize(s,    out,n,parts,i,p,lo,hi,j) {
        n = split(s, parts, /[ ,]+/)
        out = ""
        for (i = 1; i <= n; i++) {
            p = parts[i]
            if (p == "") continue
            if (p ~ /-/) {
                split(p, r, /-/)
                lo = r[1] + 0; hi = r[2] + 0
                for (j = lo; j <= hi; j++) out = out (out == "" ? "" : ",") j
            } else {
                out = out (out == "" ? "" : ",") p + 0
            }
        }
        return out
    }
    function compress(s,    n,a,i,j,t,out,start,prev,first) {
        n = split(s, a, /,/)
        for (i = 1; i <= n; i++) a[i] = a[i] + 0
        for (i = 1; i <= n; i++)
            for (j = i + 1; j <= n; j++)
                if (a[j] < a[i]) { t = a[i]; a[i] = a[j]; a[j] = t }
        if (n == 0) return ""
        out = ""; start = a[1]; prev = a[1]; first = 1
        for (i = 2; i <= n; i++) {
            if (a[i] == prev + 1) { prev = a[i]; continue }
            out = out (first ? "" : ",") (start == prev ? start : start "-" prev)
            first = 0; start = a[i]; prev = a[i]
        }
        out = out (first ? "" : ",") (start == prev ? start : start "-" prev)
        return out
    }
    $1 in freq { freq[$1] = freq[$1] "," $2; next }
    { freq[$1] = $2; order[++k] = $1 }
    END {
        n = k
        if (n == 0) { print "E_CORE= P1_CORE= P2_CORE= HP_CORE="; exit }
        e  = compress(normalize(freq[order[1]]))
        hp = compress(normalize(freq[order[n]]))
        p1 = (n >= 3) ? compress(normalize(freq[order[2]])) : ""
        p2 = (n >= 4) ? compress(normalize(freq[order[3]])) : ""
        if (hp == "") hp = e
        print "E_CORE=\"" e "\""
        print "P1_CORE=\"" p1 "\""
        print "P2_CORE=\"" p2 "\""
        print "HP_CORE=\"" hp "\""
    }')"

ALL_CORE=$(cat /sys/devices/system/cpu/present 2>/dev/null)
[ -z "$ALL_CORE" ] && ALL_CORE="$HP_CORE"
if [ -n "$P1_CORE" ] && [ -n "$P2_CORE" ]; then
    P_CORE="${P1_CORE},${P2_CORE}"
elif [ -n "$P1_CORE" ]; then
    P_CORE="$P1_CORE"
else
    P_CORE="$P2_CORE"
fi

ui_print "- CPU: hp=$HP_CORE p2=$P2_CORE p1=$P1_CORE e=$E_CORE all=$ALL_CORE"

# 展开语义占位符生成最终配置
if [ -f "$MODPATH/threads.json" ]; then
    sed -e "s/{e_core}/$E_CORE/g" \
        -e "s/{p1_core}/$P1_CORE/g" \
        -e "s/{p2_core}/$P2_CORE/g" \
        -e "s/{p_core}/$P_CORE/g" \
        -e "s/{hp_core}/$HP_CORE/g" \
        -e "s/{all_core}/$ALL_CORE/g" \
        "$MODPATH/threads.json" > "$TARGET/threads.json" 2>/dev/null
    ui_print "- 配置已按拓扑生成"
else
    [ -f "$TARGET/threads.json" ] || ui_print "- 缺少模板, 请手动配置 threads.json"
fi

ui_print "- Aether OptExt 安装完成"
ui_print "- 日志: /sdcard/Android/Aether/threads_log.txt"
