**Hello World!**

**island_v4计划**
> 思考脚本如何连贯启动
> island 的定位不是只显示歌词（未来还有可能显示专辑封面），还可以显示一些
> 有用的信息，如日历，天气，通知

**启动ncmpcpp**
```bash
kitty --class ncmpcpp_island ncmpcpp
```
**灵动岛需要的依赖**
```bash
sudo pacman -S --needed socat waybar grep sed
```
**需要配置的快捷键**
```bash
# niri快捷键脚本启动
Ctrl+M hotkey-overlay-title="island_mpd" {spawn "~/.config/waybar/scripts/island/music_start.sh";}
```
