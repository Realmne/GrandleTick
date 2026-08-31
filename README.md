# GrandleTick

GrandleTick 是一个 macOS 菜单栏学习计时工具。

它会自动记录你在应用、学习网站和 PDF 上花费的时间，不需要每次手动开始或停止。适合用 Bilibili 看课程、在「预览」里读资料，或者想简单回顾每天学习情况的人。

这是一个个人项目，不是商业软件。它只想安静地做好一件事：帮你看清时间花在了哪里。

## 特色功能

### 自动计时

- 根据当前使用的应用或网页自动计时
- 切换到其他内容时自动更新，无需手动操作
- 菜单栏随时显示今日累计时长
- 区分学习与休闲时间

### 学习内容识别

- 自动统计「预览」中的 PDF 阅读时间
- 支持 Safari、Google Chrome 和 Microsoft Edge
- 可以自定义需要计入学习的应用和网站
- 对 Bilibili 视频进行单独分类，尽量避免把娱乐视频算进学习时间

### 数据中心

- 查看今天、本周、本月、今年或全部历史
- 查看学习趋势、学习与休闲占比
- 查看常用应用、网站和 PDF
- 搜索并按月份查询指定 App、域名或 PDF 的使用时长
- 按日期查看具体学习内容
- 支持搜索、筛选和删除记录

### 年度报告

根据本地记录生成年度学习回顾，包括：

- 全年学习时长和活跃天数
- 学习时间分布
- 常用应用、网站和 PDF
- 最长连续学习天数
- 年度学习习惯总结

### 定时休息

- 支持 25、45、60 分钟快捷倒计时
- 可以自定义提醒时间
- 到点后提醒休息
- 支持延后 5 分钟

## 界面预览

以下截图使用演示数据生成，不包含真实个人记录。

### 菜单栏

![GrandleTick 菜单栏界面](README-assets/menu-popup-demo.png)

### 白名单管理

![GrandleTick 白名单管理](README-assets/whitelist-demo.png)

### 数据中心

![GrandleTick 数据中心](README-assets/statistics-demo.png)

## 安装

1. 从 [GitHub Releases](https://github.com/YohanJx/GrandleTick/releases) 下载最新版本
2. 将 `GrandleTick.app` 放入「应用程序」
3. 首次启动后授予“辅助功能”权限
4. 点击菜单栏中的时钟图标开始使用

如果 macOS 提示“App 已损坏，打不开”，可以在终端执行：

```bash
sudo xattr -cr /Applications/GrandleTick.app
```

然后重新打开应用。

## 使用方法

1. 启动 GrandleTick
2. 在白名单中添加需要计入学习的应用和网站
3. 正常学习，软件会自动记录时间
4. 打开数据中心查看趋势和明细

## 数据与隐私

- 所有记录保存在本地
- 不需要注册账号
- 不提供云同步
- 不会将学习记录上传到 GrandleTick 的服务器

数据保存在：

```text
~/Library/Application Support/GrandleTick
```

## 当前限制

- 仅支持 macOS 14.0 及以上版本
- 需要授予辅助功能权限
- PDF 自动识别目前只支持系统自带的「预览」
- 浏览器支持 Safari、Google Chrome 和 Microsoft Edge
- Bilibili 分类无法保证百分之百准确

## 说明

GrandleTick 来自我自己的学习记录需求。它不是待办工具，也不是一套复杂的效率方法，只是一个尽量少打扰、能够自动记录的菜单栏小工具。
