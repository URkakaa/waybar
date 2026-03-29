**Hello World!**

#### **island_v4计划**
> 思考脚本如何连贯启动
island 的定位不是只显示歌词（未来还有可能显示专辑封面），还可以显示一些
有用的信息，如日历，天气，通知

##### 启动ncmpcpp

```bash
kitty --class ncmpcpp_island ncmpcpp
```
##### 进行了一个危险的操作，全局修改通知

```bash
# 备份原 notify-send
sudo mv /usr/bin/notify-send /usr/bin/notify-send-original

# 软链接到你的通知脚本（替换为实际路径）
sudo ln -s /home/kakaa/.config/waybar/scripts/island/notify.sh /usr/bin/notify-send

```
