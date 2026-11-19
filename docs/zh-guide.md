# 中文导读

英文的 `README.md` 和 `docs/architecture.md` 是行为说明的依据。若中英文不一致，以英文为准。本文只帮助快速阅读，不增加功能，也不表示项目已经完成。

## 这是什么

这是一份私有草案：PostgreSQL 初始 schema、合成夹具，以及数据库不变量测试。它不是可用的三维资产管理系统，没有 React / Three.js 界面，没有 glTF 或 IFC 解析器，没有账号，也没有部署。

这些文件不保证任何积分、额度或外部计划会接受本项目。

## 两条身份，不要混用

- 资产 UUID 和 `asset_tag` 是保管身份，由数据库分配，创建后不能改。
- 模型身份是某个模型版本里的 glTF `extras` 稳定 ID，或 IFC GlobalId。
- Three.js 运行时 UUID 和节点下标不是身份，schema 里没有这些列。
- 接受模型和资产的对应关系，不会改变资产当前房间。

资产当前房间只在登记时写入，或在调拨被 `confirm_transfer` 确认时更新。画面、文件差异和摄像机都不会自动产生调拨。观察结果和保管房间不一致时，只记一条待复核记录，不改房间，也不悄悄改对应关系。

## 本地检查

需要本机已有 PostgreSQL 14 或更新版本。脚本只会删除并重建名为 `asset_mvp_starter_test` 的数据库。

```bash
chmod +x db/tests/run.sh
./db/tests/run.sh
```

夹具里的 `Synthetic cabinet`、`BLD-NORTH` 等都是虚构标签，不是真实的人、客户或场所。

## 草案问题单

`docs/issues/` 里是尚未提交到任何平台的问题草稿。`docs/devin-session-prompt.md` 只允许将来单独做 001，并且要先由人在产品里设置消费上限。不要据此宣称系统已经实现。
