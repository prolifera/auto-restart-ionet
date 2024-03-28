# auto-restart-ionet
目前适配于linux服务器，需要root用户

每30分钟一次，监测ionet容器状况，当遇到以下三种情况之一时，重启容器
- ionet-launch容器不存在，同时monitor和vc容器不存在
- ionet-launch容器持续时间超过一小时
- vc和monitor存在，但是两个容器的cpu占用连续30s是0%

# 依赖配置
## 必要环境变量
- $DEVICE_ID
- $DEVICE_NAME
- $USER_ID
以上均可从ionet的启动命令拿到。

## 可选环境变量 
$DINGTALK_ACCESS_TOKEN (钉钉机器人的token）
如果该环境变量存在，当检测到需要重启时，会发送提醒到钉钉，并将重启执行结果发送到钉钉，如下所示：
![image](https://github.com/prolifera/auto-restart-ionet/assets/28798140/a8670b5a-7972-487d-998b-15d8179a9d5c)


# 启动脚本
```
curl -s https://gist.githubusercontent.com/mgintoki/7ac63e2c9f80154e0b865a2018dc3f86/raw | bash
```

该脚本会自动执行安装流程，并注册到开机启动
```
root@ecs-73663768-004:~# curl -s https://gist.githubusercontent.com/mgintoki/7ac63e2c9f80154e0b865a2018dc3f86/raw | bash
[Unit]
Description=Auto Restart ionet Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/bash -c 'while true; do /root/auto-restart-ionet.sh; sleep 1800; done'

[Install]
WantedBy=multi-user.target
Created symlink /etc/systemd/system/multi-user.target.wants/auto-restart-ionet.service → /etc/systemd/system/auto-restart-ionet.service.
安装完成，ionet-auto-restart服务已启动。
```

安装完毕后，使用 
> journalctl -u auto-restart-ionet.service
查看 日志

# 移除脚本

systemctl stop auto-restart-ionet.service

sudo systemctl disable auto-restart-ionet.service

sudo rm /etc/systemd/system/auto-restart-ionet.service

