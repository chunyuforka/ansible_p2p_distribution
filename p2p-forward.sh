#!/bin/bash
# p2p_forward.sh
#
# 用法：
#   ./p2p_forward.sh <global_inventory> <local_ip> <fork> <src_path> <dest_path> [rsync_port]
#
# 参数说明：
#   global_inventory: 全量节点 IP，逗号分隔（例如 "10.0.0.1,10.0.0.2,10.0.0.3,10.0.0.4"）
#   local_ip:         当前节点 IP（必须存在于 global_inventory 中）
#   fork:             裂变值，每个发送节点向下转发的目标数量（例如 2 或 3）
#   src_path:         待传输的文件或目录路径（控制机上的源路径）
#   dest_path:        目标路径（各节点上希望存放文件或目录的目录，可以与 src_path 不同）
#   rsync_port:       （可选）rsync 监听端口，默认 873
#
# 功能：
#   1. 根据 global_inventory 和 local_ip 计算发送映射（发送端 -> 目标列表）。
#   2. 脚本内部自动生成随机锁目录，用于存放锁文件 complete.lock 及临时配置文件。
#   3. 根据 src_path 计算待传输对象名称（src_item）。
#   4. 如果当前节点为控制机（全量 IP 列表第一项），则不启动 rsync 监听，直接生成锁文件；
#      否则启动 rsync 守护进程，监听两个模块：
#         [data] 模块：接收上游数据，监听目录为 dest_path。
#         [lock] 模块：接收上游锁文件，监听目录为随机生成的锁目录。
#   5. 非控制机节点：轮询检测锁文件是否生成，确认上游传输完成。
#   6. 向下游节点并行转发数据和锁文件：
#         - 如果当前节点为控制机，则发送 src_path；
#         - 否则发送 dest_path/〈src_item〉。
#         传输数据要求连续成功2次；传输前轮询等待对端 rsync 监听就绪（最多3分钟）。
#         成功后，再发送锁文件。
#   7. 转发完成后关闭 rsync 守护进程（如果启动了）、清理临时文件，并退出程序。
#

# -------------------------------
# 参数解析及基本检查
# -------------------------------
if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <global_inventory> <local_ip> <fork> <src_path> <dest_path> [rsync_port]"
    exit 1
fi

global_inventory="$1"
local_ip="$2"
fork="$3"
src_path="$4"
dest_path="$5"
rsync_port="${6:-873}"

# 待传输对象基本名称
src_item=$(basename "$src_path")

echo "待传输对象: $src_path"
echo "目标路径: $dest_path"
echo "对象名称: $src_item"
echo "----------------------------------"

# -------------------------------
# 内部生成随机锁目录及临时配置文件路径
# -------------------------------
lock_dir=$(mktemp -d /tmp/rsync_lock.XXXXXX)
LOCK_FILE="${lock_dir}/complete.lock"
CONFIG_FILE="${lock_dir}/rsync.conf"

echo "随机生成锁目录: ${lock_dir}"
echo "锁文件路径: ${LOCK_FILE}"
echo "----------------------------------"

# -------------------------------
# 1. 计算发送映射（发送端 -> 目标列表）
# -------------------------------
IFS=',' read -r -a inventory_array <<< "$global_inventory"
n=${#inventory_array[@]}

declare -A send_map

# 按“完全树”模型构造映射：对于每个节点 i，其目标为下标 fork*i+1 到 fork*i+fork（在范围内）
for i in "${!inventory_array[@]}"; do
    children=()
    for ((j=1; j<=fork; j++)); do
        child_index=$(( fork * i + j ))
        if [ $child_index -lt $n ]; then
            children+=("${inventory_array[$child_index]}")
        fi
    done
    if [ ${#children[@]} -gt 0 ]; then
        child_str=$(IFS=','; echo "${children[*]}")
        send_map["${inventory_array[$i]}"]="$child_str"
    fi
done

echo "发送映射计算结果："
for sender in "${!send_map[@]}"; do
    echo "  发送端: $sender -> 目标: ${send_map[$sender]}"
done
echo "----------------------------------"

echo "本机 IP: $local_ip"
if [ -z "${send_map[$local_ip]}" ]; then
    echo "本机无下游目标，仅作为接收节点。"
else
    echo "本机下游目标: ${send_map[$local_ip]}"
fi
echo "----------------------------------"

# -------------------------------
# 判断是否为控制机（全量清单中的第一项）
# -------------------------------
first_ip=$(echo "$global_inventory" | cut -d',' -f1)
if [ "$local_ip" = "$first_ip" ]; then
    echo "当前为控制机（起始节点），不启动 rsync 监听，直接生成锁文件。"
    skip_listen=true
    # 直接生成锁文件
    touch "$LOCK_FILE"
else
    skip_listen=false
fi

# -------------------------------
# 2. 非控制机节点启动 rsync 守护进程
# -------------------------------
if [ "$skip_listen" = "false" ]; then
    # 生成 rsync 配置文件，其中 [data] 模块的 path 为 dest_path
    cat <<EOF > "$CONFIG_FILE"
[data]
  path = ${dest_path}
  comment = Data Module
  read only = false
  list = false
  uid = root
  gid = root

[lock]
  path = ${lock_dir}
  comment = Lock Module
  read only = false
  list = false
  uid = root
  gid = root
EOF

    echo "生成的 rsync 配置文件: $CONFIG_FILE"
    cat "$CONFIG_FILE"
    echo "----------------------------------"

    echo "启动 rsync 守护进程（监听端口 $rsync_port）..."
    mkdir -p $dest_path
    rsync --daemon --no-detach --port="$rsync_port" --config="$CONFIG_FILE" &
    rsync_pid=$!
    echo "rsync 守护进程 PID: $rsync_pid"
    echo "----------------------------------"
fi

# -------------------------------
# 3. 非控制机节点：轮询检测锁文件是否接收完毕
# -------------------------------
if [ "$skip_listen" = "false" ]; then
    echo "轮询检测是否接收到锁文件：$LOCK_FILE"
    LOCK_TIMEOUT=300  # 超时时间 300 秒
    WAIT_INTERVAL=5   # 检测间隔 5 秒
    elapsed=0
    while [ ! -f "$LOCK_FILE" ]; do
        sleep $WAIT_INTERVAL
        elapsed=$((elapsed + WAIT_INTERVAL))
        echo "等待接收锁文件... 已等待 ${elapsed} 秒"
        if [ "$elapsed" -ge "$LOCK_TIMEOUT" ]; then
            echo "Error: 超时未收到锁文件，退出。"
            kill $rsync_pid
            rm -rf "$lock_dir"
            exit 1
        fi
    done
    echo "检测到锁文件 $LOCK_FILE，确认上游传输完成。"
    echo "----------------------------------"
else
    echo "控制机跳过等待锁文件步骤。"
    echo "----------------------------------"
fi

# -------------------------------
# 辅助函数：等待远程节点端口监听
# -------------------------------
wait_for_remote() {
    local target="$1"
    local port="$2"
    local timeout=180  # 最大等待 180 秒（3 分钟）
    local interval=5
    local start_time=$(date +%s)
    while ! nc -z "$target" "$port"; do
        sleep $interval
        local current_time=$(date +%s)
        local elapsed=$(( current_time - start_time ))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Error: 等待远程节点 $target 端口 $port 超时 (超过 $timeout 秒)"
            return 1
        fi
    done
    return 0
}

# -------------------------------
# 辅助函数：执行 rsync 传输
# 参数：src, destination_url
# -------------------------------
rsync_transfer() {
    local src="$1"
    local dest_url="$2"
    rsync -avz "$src" "$dest_url" > /dev/null
    return $?
}

# -------------------------------
# 4. 并行根据发送映射转发数据及锁文件
# -------------------------------
if [ -n "${send_map[$local_ip]}" ]; then
    targets="${send_map[$local_ip]}"
    echo "本机 $local_ip 为发送节点，目标为: $targets"
    IFS=',' read -r -a target_array <<< "$targets"

    declare -a send_pids=()

    for target in "${target_array[@]}"; do
        (
            echo "--------------------------------------------------"
            # 如果目标 IP 与本机相同，则直接进行本地复制
            if [ "$target" = "$local_ip" ]; then
                echo "目标节点 $target 与本机相同，直接本地复制数据"
                # 数据复制：复制待传输对象到 dest_path 下（覆盖或更新）
                mkdir -p  ${dest_path} 
                rsync -av ${src_path} ${dest_path} 
                echo "本地复制完成。"
                sleep 3
                exit 0
            fi

            echo "等待目标节点 $target 的 rsync 监听..."
            if ! wait_for_remote "$target" "$rsync_port"; then
                echo "跳过目标节点 $target 传输。"
                exit 1
            fi

            # 数据传输尝试：要求连续成功两次
            success_count=0
            attempt=0
            max_attempts=10
            while [ $success_count -lt 2 ] && [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt + 1))
                echo "尝试第 $attempt 次向 $target 传输数据..."
                if [ "$skip_listen" = "true" ]; then
                    # 如果是控制机，直接发送 src_path
                    rsync_transfer "$src_path" "rsync://${target}:${rsync_port}/data/"
                else
                    # 非控制机，发送 dest_path 下的 src_item
                    rsync_transfer "${dest_path}/${src_item}" "rsync://${target}:${rsync_port}/data/"
                fi
                ret=$?
                if [ $ret -eq 0 ]; then
                    success_count=$((success_count + 1))
                    echo "第 $attempt 次数据传输成功 (累计成功 $success_count 次)。"
                else
                    echo "第 $attempt 次数据传输失败，重试..."
                    sleep 5
                fi
            done

            if [ $success_count -lt 2 ]; then
                echo "Error: 向 $target 传输数据未达到要求的2次成功，跳过该节点。"
                exit 1
            fi

            echo "等待目标节点 $target 的锁模块监听..."
            if ! wait_for_remote "$target" "$rsync_port"; then
                echo "Error: 目标节点 $target 锁模块等待超时，跳过传输锁文件。"
                exit 1
            fi

            echo "向下游节点 $target 传输锁文件..."
            rsync_transfer "$LOCK_FILE" "rsync://${target}:${rsync_port}/lock/"
            if [ $? -eq 0 ]; then
                echo "锁文件传输给 $target 成功。"
            else
                echo "锁文件传输给 $target 失败。"
            fi
            echo "--------------------------------------------------"
        ) &
        send_pids+=($!)
    done

    # 等待所有后台发送任务完成
    for pid in "${send_pids[@]}"; do
        wait $pid
    done
else
    echo "本机 $local_ip 不在发送映射中，仅作为接收节点，无需转发。"
fi
echo "----------------------------------"

# -------------------------------
# 5. 关闭 rsync 监听（如果已启动），清理临时文件，退出程序
# -------------------------------
if [ "$skip_listen" = "false" ]; then
    echo "关闭本地 rsync 守护进程 (PID: $rsync_pid) ..."
    kill $rsync_pid
fi

echo "删除临时锁目录: $lock_dir"
rm -rf "$lock_dir"

echo "所有下游节点传输完成，程序退出。"
exit 0

