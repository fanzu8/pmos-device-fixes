# pmos-device-fixes

postmarketOS 设备/硬件修复集合。

每个修复放在独立目录里，包含：

- 问题现象、根因、踩坑记录
- 内核补丁 / 内核配置
- UCM 或其他配置文件
- 构建、安装、验证脚本
- GitHub Actions 构建出的模块/产物

---

## 修复列表

| Device | Subsystem | Fix | Kernel | Status | Docs |
|---|---|---|---|---|---|
| OnePlus 6 (enchilada) | Audio | WCD934x capture: MCLK + PulseAudio capture volume | 6.16.7 / 7.1-rc1 | verified on 6.16.7 | [README](devices/oneplus-enchilada/audio/wcd934x-mic/README.md) |

---

## 目录约定

```
devices/<vendor>-<codename>/<subsystem>/<fix>/
```

例如：

```
devices/oneplus-enchilada/audio/wcd934x-mic/
├── README.md
├── patches/
├── config/
├── ucm/
├── scripts/
└── prebuilt/
```

以后新增设备/修复：

```
devices/xiaomi-beryllium/audio/...
devices/pine64-pinephone/display/...
devices/oneplus-enchilada/camera/...
```

每个 fix 自带 README，写清楚：

1. 现象
2. 根因
3. 改动
4. 踩坑
5. 构建/安装/验证
6. 上游链接（如果有）

---

## CI 与产物

每个 fix 一个 workflow，放在：

```
.github/workflows/<device>-<fix>.yml
```

用 `paths` 过滤，只有对应目录变化时才构建。

当前：

| Workflow | Artifacts |
|---|---|
| `oneplus-enchilada-wcd934x.yml` | `oneplus-enchilada-wcd934x-6.16.7`、`oneplus-enchilada-wcd934x-7.1-rc1` |

Actions：

```
https://github.com/fanzu8/pmos-device-fixes/actions
```

每个 artifact 包含：

```
snd-soc-wcd934x.ko.zst
snd-soc-wcd934x.ko.zst.sha256
VERMAGIC.txt
HiFi.conf
VoiceCall.conf
INSTALL.txt
```

---

## 新增一个 fix

1. 建目录：

```sh
mkdir -p devices/<vendor>-<codename>/<subsystem>/<fix>
```

2. 放入 `README.md`、`patches/`、`config/`、`scripts/` 等。
3. 在 `.github/workflows/` 加一个 workflow，写 `paths` 过滤。
4. 在上面的“修复列表”里加一行。
5. 提交前扫描密钥/凭证。

---

## 安全

本仓库不包含任何 token、密钥、密码或凭据。

- CI 不需要 secrets
- 提交前会扫描常见密钥/令牌格式（`ghp_` / `gho_` / `glpat` / `PRIVATE KEY` 等）
- `.gitignore` 忽略 `.env`、`*.pem`、`*.key`、`*.p12`、`secrets.*`

---

## License

- 内核补丁：GPL-2.0（见 `LICENSE`）
- UCM 配置：BSD-3-Clause（来自 pmOS / sdm845-mainline UCM）
- 各 fix 目录内的说明为准
