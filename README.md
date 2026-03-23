# 数据关联分析平台 - Flutter移动版

## 功能
- 📁 选择本地数据目录
- 📊 扫描Excel文件
- 🔗 多表Inner Join关联查询
- 📤 导出Excel结果

## 在GitHub上自动构建APK

### 步骤1: 上传代码到GitHub
```bash
# 在GitHub创建新仓库 data-analyzer-app
# 然后推送代码:
git remote add origin https://github.com/你的用户名/data-analyzer-app.git
git add .
git commit -m "init"
git branch -M main
git push -u origin main
```

### 步骤2: 触发自动构建
1. 打开你的GitHub仓库
2. 点击 Actions 标签
3. 点击 "Build APK" workflow
4. 点击 "Run workflow" 按钮

### 步骤3: 下载APK
构建完成后，在 Artifacts 中下载 `app-debug`

## 本地构建(需要8GB+内存)
```bash
flutter pub get
flutter build apk --debug
```

## 技术栈
- Flutter 3.24
- excel: Excel读取
- file_picker: 文件选择
- shared_preferences: 配置存储
- path_provider: 路径处理

## 视频教程
[查看B站教程](https://www.bilibili.com/video/xxx)