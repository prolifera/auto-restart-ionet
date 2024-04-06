#!/bin/bash
cd /root
# 从环境变量读取配置
device_id=$DEVICE_ID
user_id=$USER_ID
device_name=$DEVICE_NAME
access_token=$DINGTALK_ACCESS_TOKEN
system=linux  # 认为系统全是Ubuntu，此处简化处理
gpu=true  # 此值根据实际情况进行配置

os="Linux"  # 直接设定操作系统为Linux

echo '开始执行脚本'

# 检查start_ionet.sh是否存在
if [ ! -f "/root/start_ionet.sh" ]; then
    echo "未找到start_ionet.sh，现在下载并赋予权限..."
    curl -fsSL https://gist.githubusercontent.com/mgintoki/fce64e588d06db6e1e4e5a38d6b7edd6/raw -o /root/start_ionet.sh
    chmod +x /root/start_ionet.sh
fi

# 发送钉钉通知
send_dingtalk_notification() {
    reason=$1
    detail=$2  # 添加一个详细说明的参数

    # 如果access_token为空，则直接返回
    if [ -z "$access_token" ]; then
        echo "DingTalk access_token未设置，跳过发送通知。"
        return
    fi

    content="ionet重启通知: 设备ID: ${device_id}, 设备名称: ${device_name}, 原因: ${reason}, 详情: ${detail}"
    response=$(curl -s "https://oapi.dingtalk.com/robot/send?access_token=${access_token}" \
         -H 'Content-Type: application/json' \
         -d '{
              "msgtype": "text",
              "text": {
                  "content": "'"${content}"'"
              }
            }')
    echo "发送钉钉消息，返回值: $response"
}

execute_and_notify() {
    # 创建一个临时文件用于保存脚本输出
    temp_file=$(mktemp)

    # 执行脚本，实时打印输出到控制台，并将输出同时保存到临时文件
    /root/start_ionet.sh 2>&1 | tee "$temp_file"

    # 获取最后5行
    result=$(tail -n 5 "$temp_file")

    # 检查是否包含特定字符串以确定重启是否成功
    if echo "$result" | grep -q "Status: Downloaded newer image for ionetcontainers/io-launch"; then
        reason="重启成功"
    else
        reason="重启失败"
    fi

    # 构建通知内容详情
    detail="${result}"

    # 发送钉钉通知
    send_dingtalk_notification "$reason" "$detail"

    # 删除临时文件
    rm "$temp_file"
}

echo '开始检查容器状态'

# 检查容器状态
monitor_running=$(docker ps | grep -c "io-worker-monitor")
vc_running=$(docker ps | grep -c "io-worker-vc")
launch_running=$(docker ps | grep -c "io-launch")

# 第一种重启规则: monitor和vc没起来，且launch容器也没起来
if [[ monitor_running -eq 0 && vc_running -eq 0 && launch_running -eq 0 ]]; then
    echo "所有必要的容器都已停止，正在初始化重启过程..."
    send_dingtalk_notification "所有必要的容器都已停止" "容器io-worker-monitor、io-worker-vc和io-launch均未运行"
    execute_and_notify
else
    echo '容器检测完毕...'
fi

echo '开始检查CPU占用情况'

# 第二种重启规则 ionet-launch 运行时间大于1小时
echo '检查io-launch容器运行时间...'

# 检查io-launch容器是否存在并且运行时间大于1小时
io_launch_info=$(docker ps --format '{{.Image}} {{.Status}}' | grep "io-launch")
if [[ ! -z "$io_launch_info" && "$io_launch_info" == *"hour"* ]]; then
    echo "io-launch容器已运行超过1小时，正在初始化重启过程..."
    send_dingtalk_notification "io-launch运行时间过长" "io-launch容器已运行超过1小时，即将进行重启操作"
    execute_and_notify
    exit 0
fi

# 第三种重启规则 monitor和vc的容器cpu占用率连续30s都是0.00%
if [[ monitor_running -eq 1 && vc_running -eq 1 ]]; then
    zero_cpu_count=0
    for i in {1..5}
    do
        # 获取并打印容器统计信息
        docker_stats_result=$(docker stats --no-stream)
        echo "当前的容器统计信息："
        echo "$docker_stats_result"
        # 获取容器统计信息，去掉表头
        container_stats=$(docker stats --format "{{.CPUPerc}}" --no-stream | grep -v "CPU %")

        # 计算CPU使用率为0.00%的容器数量
        zero_cpu_containers=$(echo "$container_stats" | awk '$1 == "0.00%"' | wc -l)

        # 计算总容器数量
        total_containers=$(echo "$container_stats" | wc -l)

        # 判断是否没有两个容器在运行
        if [[ $total_containers -lt 2 ]]; then
            echo "没有两个容器在运行，正在初始化重启过程..."
            send_dingtalk_notification "容器数量不足" "检测到运行的容器少于两个，即将进行重启操作"
            execute_and_notify
            exit 0  # 退出脚本
        fi

            # 判断两个容器的CPU使用率是否都不为0.00%
        if [[ $total_containers -eq 2 ]]; then
            # 如果两个容器的CPU使用率都不为0.00%，则重置计数器并退出
            if [[ $zero_cpu_containers -eq 0 ]]; then
                echo "一次检查中两个容器的CPU占用率都大于0, 结束检查"
                zero_cpu_count=0
                exit 0
            else
                ((zero_cpu_count++))
            fi
        fi
    
        # 如果计数器小于20，继续检查
        if [[ $zero_cpu_count -lt 20 ]]; then
            echo "正在检查... ($i/20)"
            sleep 5
        else
            echo "连续20次检测到至少一个容器的CPU使用率为0.00%，可能需要重启..."
            # 这里你可以调用发送钉钉通知的函数和执行重启的函数
            send_dingtalk_notification "CPU使用率检测" "连续20次检测到至少一个容器的CPU使用率为0.00%，考虑重启"
            execute_and_notify
            break
        fi
    done

    if [[ $zero_cpu_count -ne 20 ]]; then
        echo "20次检查后，未发现需要重启的条件。"
    fi
else
    echo "io-launch执行中，或是必要的容器未全部运行，不执行重启操作。"
fi
