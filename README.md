# WCD934x capture fix (OnePlus 6 / enchilada, postmarketOS)

[![build-wcd934x](https://github.com/fanzu8/wcd934x-capture-fix/actions/workflows/build.yml/badge.svg)](https://github.com/fanzu8/wcd934x-capture-fix/actions/workflows/build.yml)

修复 OnePlus 6（enchilada）在 postmarketOS 下**录音全 0、麦克风无声**的问题。

- 内核：`6.16.7-sdm845`（`sdm845-mainline/linux` tag `sdm845-6.16.7-r0`）
- 系统：postmarketOS v25.12
- Codec：Qualcomm WCD934x
- 测试设备：OnePlus 6 (enchilada)

---

## 现象

- 扬声器、耳机播放正常
- `arecord` / `parecord` / 任何录音应用都得到纯数字 0：

```
arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 2 /tmp/a.wav
# frames 96000  rms 0.0  peak 0
```

- 例外：当 codec 的某个输出（例如听筒）**同时有播放流**时，录音才有声音。
  这说明问题在 codec 的时钟/偏置，而不是麦克风本身。

---

## 根因（两个独立问题叠加）

### 1. 内核 wcd934x：采集路径没有依赖 MCLK

WCD934x 的 ADC/DMIC 需要 MCLK，以及和 MCLK 一起打开的模拟偏置（ANA_BIAS）。

- 播放路径：`INTn_CLK` supply 会调用 `wcd934x_codec_enable_mclk`
- 采集路径：ADC/DMIC 在 DAPM 里**没有**依赖 `MCLK`

结果录音时：

- `MCLK` DAPM widget 一直是 Off
- `ANA_BIAS` 寄存器 `0x601` 一直是 `0x00`
- ADC/DEC 虽然显示 On，但没有时钟/偏置
- SLIMBUS TX 送出的全是 0

### 2. PulseAudio UCM：默认音量把 ADC 钳到 mute

采集音量控制 `ADC2/3/4 Volume` 的 dB 范围是 `0 .. +5 dB`，并且 **0 dB 就是 mute**。

PulseAudio 默认输入音量约 83%（约 `-5.8 dB`），低于 0 dB 下限，被钳位到 0：

```
amixer -c0 sget ADC4
# Mono: 0 [0%] [-99999.99dB]
```

即使内核已经修好，只要 PulseAudio 默认音量生效，麦克风仍然是静音。

---

## 改动

### 内核：`sound/soc/codecs/wcd934x.c`

在 DAPM 路由表里给 ADC1-4、DMIC0-5 增加 `MCLK` 依赖：

```c
{"ADC1", NULL, "MCLK"},
{"ADC2", NULL, "MCLK"},
{"ADC3", NULL, "MCLK"},
{"ADC4", NULL, "MCLK"},
{"DMIC0", NULL, "MCLK"},
...
{"DMIC5", NULL, "MCLK"},
```

补丁：

```
patches/0001-ASoC-codecs-wcd934x-enable-MCLK-for-the-capture-path.patch
```

### UCM：OnePlus 6 采集设备

去掉 `HiFi.conf` / `VoiceCall.conf` 里采集设备的：

```
CaptureMixerElem "ADC4"
CaptureVolume "ADC4 Volume"
```

让 PulseAudio 使用软件音量；硬件增益保持 UCM BootSequence 的：

```
ADC = 16  (4 dB)
DEC = 75  (-9 dB)
```

补丁/文件：

```
patches/0002-OnePlus-enchilada-use-software-volume-for-capture.patch
ucm/HiFi.conf
ucm/VoiceCall.conf
```

---

## 踩坑记录

1. **先怀疑 PulseAudio，后来用 `arecord` 直连 ALSA 仍然全 0**  
   说明不是应用/服务器层的问题，必须往下查 codec。

2. **DAPM 显示 ADC/MIC BIAS 都 On，但 `ANA_BIAS` 还是 0**  
   `0x601 = 0x00`。DAPM 的 On 只代表寄存器 bit 被置位，不代表模拟偏置/时钟真的开了。

3. **播放能打开 MCLK，录音不行**  
   播放走 `INTn_CLK`，录音没有对应的 clock supply。  
   临时验证：录音时同时放一个**静音**的听筒流，MCLK 被打开，麦克风立刻有数据。

4. **只去掉 `CaptureVolume` 或只去掉 `CaptureMixerElem` 都还会 mute**  
   两者都会让 PulseAudio 去控制 ADC 音量，必须**两个都去掉**。

5. **把 `CaptureMixerElem` 改成 `DEC7` 也不行**  
   PulseAudio 会把 50% 映射到 `+21 dB`，很容易削波。

6. **改的是内核模块，不能 `insmod` 热加载**  
   `snd_soc_wcd934x` 被声卡占用，运行中无法卸载。  
   必须替换 `.ko.zst` → `depmod` → 重启。

7. **重新编译必须匹配内核**  
   - 同一个源码 tag（`sdm845-6.16.7-r0`）
   - 手机上的 `/proc/config.gz`
   - 本内核 `CONFIG_MODVERSIONS` / `CONFIG_MODULE_SIG` 都是关闭的
   - vermagic 必须完全一致：`6.16.7-sdm845 SMP preempt mod_unload aarch64`

8. **模块是 zstd 压缩的**  
   内核开了 `CONFIG_MODULE_COMPRESS_ZSTD=y`，安装的模块文件是 `.ko.zst`。

9. **测试音量**  
   扬声器测试用 50% 就够，不要开满，避免太吵/削波。

---

## 验证数据

扬声器播放 440 Hz 测试音 @ 50%：

| 录音源 | RMS | Peak | 440Hz 幅度 | 300Hz 幅度 |
|---|---:|---:|---:|---:|
| 默认（底部）麦克风 | 107.9 | 3248 | 88.0 | 0.0 |
| 顶部麦克风 | 90.7 | 6018 | 8.8 | 0.1 |
| 扬声器 monitor | 486.4 | 1116 | 476.0 | 0.2 |

- 440Hz 明显高于 300Hz，确认录到的是播放的测试音
- 停止录音后 `MCLK` / `ADC` / `MIC BIAS` 关闭，`ANA_BIAS=0`，不会额外耗电

---

## 目录结构

```
.
├── patches/
│   ├── 0001-ASoC-codecs-wcd934x-enable-MCLK-for-the-capture-path.patch
│   └── 0002-OnePlus-enchilada-use-software-volume-for-capture.patch
├── config/
│   └── kernel.config              # 手机 /proc/config.gz
├── ucm/
│   ├── HiFi.conf                 # 已去掉 CaptureMixerElem/CaptureVolume
│   └── VoiceCall.conf
├── prebuilt/
│   ├── snd-soc-wcd934x.ko.zst    # 已在本机验证过的模块
│   └── snd-soc-wcd934x.ko.zst.sha256
├── scripts/
│   ├── build-module.sh           # 本地 Docker 构建
│   └── install-on-phone.sh       # 安装到手机
└── .github/workflows/build.yml   # CI：编译并上传 .ko.zst
```

---

## 本地构建

依赖：Docker（arm64）。

```sh
./scripts/build-module.sh /path/to/linux-sdm845-6.16.7-r0
```

脚本内部使用 `alpine:3.23` + clang 21（和原内核 `CONFIG_CC_VERSION_TEXT` 一致）：

```sh
make ARCH=arm64 LLVM=1 olddefconfig
make ARCH=arm64 LLVM=1 modules_prepare -j$(nproc)
make ARCH=arm64 LLVM=1 M=sound/soc/codecs KBUILD_MODPOST_WARN=1 modules -j$(nproc)
zstd -19 -f -o snd-soc-wcd934x.ko.zst sound/soc/codecs/snd-soc-wcd934x.ko
```

检查：

```sh
objdump -s -j .modinfo snd-soc-wcd934x.ko | grep vermagic
# vermagic=6.16.7-sdm845 SMP preempt mod_unload aarch64
```

---

## CI 产物

GitHub Actions 会在以下情况自动编译：

- push 到 `main`
- 手动 `workflow_dispatch`（可指定 `kernel_tag`）

产物（Actions → 对应 run → Artifacts）：

```
snd-soc-wcd934x.ko.zst
snd-soc-wcd934x.ko.zst.sha256
HiFi.conf
VoiceCall.conf
INSTALL.txt
```

CI 使用 `ubuntu-24.04-arm` 原生 arm64 runner + Docker `alpine:3.23`，
和本地构建环境一致。

---

## 安装到手机

手机通过 USB 网络 `172.16.42.1` 连接，用户 `user`：

```sh
./scripts/install-on-phone.sh
```

或手动：

```sh
scp prebuilt/snd-soc-wcd934x.ko.zst user@172.16.42.1:/tmp/
ssh user@172.16.42.1
sudo cp /tmp/snd-soc-wcd934x.ko.zst \
  /lib/modules/6.16.7-sdm845/kernel/sound/soc/codecs/snd-soc-wcd934x.ko.zst
sudo depmod -a 6.16.7-sdm845
sudo cp HiFi.conf /usr/share/alsa/ucm2/OnePlus/enchilada/HiFi.conf
sudo cp VoiceCall.conf /usr/share/alsa/ucm2/OnePlus/enchilada/VoiceCall.conf
sudo reboot
```

重启后验证：

```sh
arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 3 /tmp/test.wav
# 应该录到环境声，而不是全 0
```

---

## 上游

- 内核 MR（sdm845-mainline/linux，目标 `sdm845/7.1-dev`）  
  https://gitlab.com/sdm845-mainline/linux/-/merge_requests/157
- UCM MR（sdm845-mainline/alsa-ucm-conf，目标 `sdm845-phones`）  
  https://gitlab.com/sdm845-mainline/alsa-ucm-conf/-/merge_requests/33

内核补丁同时可以发到 Linux 邮件列表（`linux-sound` / `linux-arm-msm`）。
这个驱动比较老，是否上游化看维护者反馈；对 pmOS 来说，上面的 GitLab MR 更直接。

---

## 注意

- 升级内核包会覆盖 `/lib/modules/.../snd-soc-wcd934x.ko.zst`，需要重新安装/编译。
- 升级 `alsa-ucm-conf-sdm845` 会覆盖 UCM 文件，需要重新应用 UCM 改动。
- 预编译模块只适用于 **6.16.7-sdm845**；内核版本变化后必须用新 tag + 新 config 重新编译。

---

## License

- 内核补丁：GPL-2.0（见 `LICENSE`）
- UCM 配置：BSD-3-Clause（来自 pmOS / sdm845-mainline UCM）
