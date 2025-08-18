# GitLab项目备份脚本

这个Python脚本可以通过管理员账号拉取GitLab上所有项目，包括所有分支，并按群组分文件夹进行备份。

## 功能特性

- 🔐 使用GitLab API访问令牌进行身份验证
- 📁 按群组自动创建文件夹结构
- 🌿 克隆所有分支（使用`--mirror`选项）
- 📝 详细的日志记录
- 📊 实时进度显示和统计信息
- ⚡ 支持分页处理大量项目
- 🔄 跳过已存在的项目，支持增量备份
- 📦 支持未分组项目的处理

## 安装依赖

```bash
pip install -r requirements.txt
```

## 获取GitLab访问令牌

1. 登录到你的GitLab实例
2. 进入 **用户设置** > **访问令牌**
3. 创建一个新的访问令牌，确保勾选以下权限：
   - `read_api` - 读取API
   - `read_repository` - 读取仓库
4. 复制生成的令牌（注意：令牌只显示一次）

## 使用方法

### 基本用法

```bash
python gitlab_backup.py --url https://gitlab.com --token YOUR_ACCESS_TOKEN
```

### 高级用法

```bash
# 指定输出目录
python gitlab_backup.py --url https://gitlab.com --token YOUR_ACCESS_TOKEN --output /path/to/backup

# 不包含未分组的项目
python gitlab_backup.py --url https://gitlab.com --token YOUR_ACCESS_TOKEN --no-ungrouped

# 查看帮助
python gitlab_backup.py --help
```

### 参数说明

- `--url`: GitLab服务器URL（必需）
- `--token`: GitLab访问令牌（必需）
- `--output`: 输出目录（默认：`gitlab_backup`）
- `--no-ungrouped`: 不包含未分组的项目

## 输出结构

脚本会在指定的输出目录中创建以下结构：

```
gitlab_backup/
├── 群组1/
│   ├── 项目1/
│   └── 项目2/
├── 群组2/
│   ├── 项目3/
│   └── 项目4/
└── 未分组/
    ├── 项目5/
    └── 项目6/
```

每个项目都是使用`git clone --mirror`克隆的，包含所有分支和标签。

## 日志文件

脚本会生成`gitlab_backup.log`日志文件，记录详细的执行过程。

## 进度显示

脚本会实时显示备份进度，包括：

- 📊 当前处理的项目进度 `[当前/总数]`
- 📈 成功克隆的项目数量
- ⏭️ 跳过的项目数量（已存在）
- ❌ 失败的项目数量
- ⏱️ 总耗时统计
- 📋 最终统计报告

示例输出：
```
[INFO] 开始GitLab备份...
[INFO] 总计需要处理 25 个项目
[INFO] 处理群组: 前端项目
[INFO] [1/25] 正在克隆项目: react-app
[SUCCESS] [1/25] 成功克隆项目: react-app
[INFO] [2/25] 正在克隆项目: vue-app
[SUCCESS] [2/25] 成功克隆项目: vue-app
...
============================================================
[SUCCESS] GitLab备份完成!
[INFO] 总群组数: 5
[INFO] 总项目数: 25
[INFO] 成功克隆: 20
[INFO] 跳过项目: 3
[INFO] 失败项目: 2
[INFO] 总耗时: 45.23 秒
[INFO] 备份目录: gitlab_backup
============================================================
```

## 注意事项

1. **权限要求**: 访问令牌需要有足够的权限来读取所有群组和项目
2. **网络连接**: 确保网络连接稳定，大量项目可能需要较长时间
3. **磁盘空间**: 确保有足够的磁盘空间存储所有项目
4. **Git安装**: 确保系统已安装Git

## 故障排除

### 常见问题

1. **API权限错误**
   - 检查访问令牌是否有正确的权限
   - 确认令牌未过期

2. **克隆失败**
   - 检查网络连接
   - 确认项目URL是否正确
   - 查看日志文件获取详细错误信息

3. **内存不足**
   - 对于大型仓库，可能需要增加系统内存
   - 考虑分批处理项目

### 调试模式

可以通过修改脚本中的日志级别来获取更详细的信息：

```python
logging.basicConfig(level=logging.DEBUG, ...)
```

## 许可证

MIT License
