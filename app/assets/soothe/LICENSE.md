# 哄睡声音（#38）

`white.wav`、`pink.wav`、`brown.wav`、`shush.wav` 由 `tool/soothe_sounds/generate.py` 用随机数**自己生成**，不含任何录音或第三方素材。

- 规格：单声道 22050 Hz 16 bit，每段 10 秒，首尾无缝循环；响度约 -24 dBFS（RMS），峰值不超过 -6 dBFS。
- 重新生成：在 `app/` 目录下运行 `python3 tool/soothe_sounds/generate.py`（只用 Python 标准库，固定随机种子）。

## 许可：CC0 1.0 通用（公共领域贡献）

在法律允许的范围内，作者放弃对这些声音文件及生成脚本的全部著作权及相关权利，任何人可以不经许可、不署名地复制、修改、分发和商用。
全文：https://creativecommons.org/publicdomain/zero/1.0/deed.zh-hans
