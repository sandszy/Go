#!/bin/sh
# 下载 App 里打包的 KataGo 模型（约 98MB）。模型太大，不放进 git 仓库。
# 用法：在仓库根目录运行 Scripts/fetch-katago-model.sh
set -eu
cd "$(dirname "$0")/.."
name=kata1-b18c384nbt-s9996604416-d4316597426
target=DengDengGo/Engine/kata1-b18c384nbt.bin.gz
if [ -f "$target" ] && gzip -t "$target" 2>/dev/null; then
    echo "模型已经在 $target"
    exit 0
fi
# 网络慢时常断，断了接着下。
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl -L --http1.1 -C - --fail -o "$target" "https://media.katagotraining.org/uploaded/networks/models/kata1/$name.bin.gz"; then
        break
    fi
    echo "下载中断，第 $attempt 次重试……"
    sleep 2
done
gzip -t "$target"
echo "模型已下载到 $target"
