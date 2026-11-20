# 第三方许可与来源

根目录 [LICENSE](LICENSE) 适用于本项目原创代码，不替代下列组件、素材或训练数据的原许可。通过 Flutter、npm 或 Python 安装的依赖遵循各自随附的许可。

## YAMNet

- 文件：`app/assets/models/yamnet.tflite`、`app/assets/models/yamnet_embed.tflite`。
- 来源：[TensorFlow YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)、[Google YAMNet 模型](https://tfhub.dev/google/yamnet/1)。
- Copyright 2019 The TensorFlow Authors. Apache License 2.0，全文见 [third_party/licenses/Apache-2.0.txt](third_party/licenses/Apache-2.0.txt)。
- `yamnet.tflite` 来自 TF Hub 的 `lite-model_yamnet_classification_tflite_1`；`yamnet_embed.tflite` 由本项目通过 `ml/src/export_yamnet.py` 从 Google YAMNet 导出单帧得分与 embedding，并进行 TFLite 动态范围量化。转换版本保留上游许可。
- YAMNet 基于 [AudioSet](https://research.google.com/audioset/) 预训练；分发模型不意味着获得原始训练录音的再分发许可。

## QR Code Generator

- 文件：`web/download/assets/qrcode.js`、`docs/design/download-page/assets/qrcode.js`。
- 来源：[kazuhikoarase/qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator)，仓内版本 2.0.4。
- QR Code 是 DENSO WAVE INCORPORATED 的注册商标。
- Copyright (c) 2009 Kazuhiko Arase. MIT License，原始版权与许可全文见 [third_party/licenses/qrcode-generator-MIT.txt](third_party/licenses/qrcode-generator-MIT.txt)。文件头的上游声明须保留。

## 哭声分类头与训练数据

- 文件：`app/assets/models/cry_head.tflite`、`app/assets/models/cry_head.json`、`ml/reports/cls-1.meta.json`。
- 内置 cls-1 分类头由本项目训练，其元数据记录训练集为 donateacry 457 条、App 用户数据 0 条。
- 训练数据来源：[gveres/donateacry-corpus](https://github.com/gveres/donateacry-corpus)，使用 `donateacry_corpus_cleaned_and_updated_data` 子集。
- 数据库许可：[Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1.0/)；单条内容许可：[Database Contents License (DbCL) 1.0](https://opendatacommons.org/licenses/dbcl/1.0/)。本模型使用该数据库的信息生成；不得将数据库或录音重新标为 MIT。对外分发模型时保留本来源说明及元数据中的 `training.license`。
- 仓库不包含原始训练录音。重新分发数据库或其衍生数据库时，须遵循原始许可的署名、许可与共享要求。
- 数据偏差、评估结果与模型使用限制见 [ml/README.md](ml/README.md#数据集与许可)。

## 安抚音频

`app/assets/soothe/` 中的白噪声、粉噪声、棕噪声和嘘声由项目脚本生成，按 CC0 1.0 提供。生成方式与许可见 [app/assets/soothe/LICENSE.md](app/assets/soothe/LICENSE.md)。
