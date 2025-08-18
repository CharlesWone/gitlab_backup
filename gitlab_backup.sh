#!/bin/bash

# GitLab项目备份脚本 (Shell版本)
# 通过管理员账号拉取GitLab上所有项目，包括所有分支，按群组分文件夹

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
GitLab项目备份脚本

用法: $0 [选项]

选项:
    -u, --url URL          GitLab服务器URL (必需)
    -t, --token TOKEN      GitLab访问令牌 (必需)
    -o, --output DIR       输出目录 (默认: gitlab_backup)
    -n, --no-ungrouped     不包含未分组的项目
    -h, --help             显示此帮助信息

示例:
    $0 -u https://gitlab.com -t YOUR_ACCESS_TOKEN
    $0 --url https://gitlab.company.com --token YOUR_TOKEN --output /path/to/backup

注意:
    - 需要安装 jq 和 curl
    - 访问令牌需要有 read_api 和 read_repository 权限
EOF
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安装，请先安装 jq"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl 未安装，请先安装 curl"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "git 未安装，请先安装 git"
        exit 1
    fi
    
    log_success "所有依赖已满足"
}

# 解析命令行参数
parse_args() {
    GITLAB_URL=""
    ACCESS_TOKEN=""
    OUTPUT_DIR="gitlab_backup"
    INCLUDE_UNGROUPED=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                GITLAB_URL="$2"
                shift 2
                ;;
            -t|--token)
                ACCESS_TOKEN="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -n|--no-ungrouped)
                INCLUDE_UNGROUPED=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查必需参数
    if [[ -z "$GITLAB_URL" ]]; then
        log_error "GitLab URL 是必需的"
        show_help
        exit 1
    fi
    
    if [[ -z "$ACCESS_TOKEN" ]]; then
        log_error "访问令牌是必需的"
        show_help
        exit 1
    fi
    
    # 移除URL末尾的斜杠
    GITLAB_URL="${GITLAB_URL%/}"
}

# 发送API请求
api_request() {
    local endpoint="$1"
    local url="${GITLAB_URL}/api/v4/${endpoint}"
    local page=1
    local per_page=100
    local all_data="[]"
    
    while true; do
        local response=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            "${url}?page=${page}&per_page=${per_page}")
        
        if [[ $? -ne 0 ]]; then
            log_error "API请求失败: $url"
            return 1
        fi
        
        local data=$(echo "$response" | jq -r '.')
        
        if [[ "$data" == "[]" ]] || [[ "$data" == "null" ]]; then
            break
        fi
        
        if [[ "$all_data" == "[]" ]]; then
            all_data="$data"
        else
            all_data=$(echo "$all_data" | jq -s '.[0] + .[1]')
        fi
        
        # 检查是否还有更多数据
        local count=$(echo "$data" | jq 'length')
        if [[ $count -lt $per_page ]]; then
            break
        fi
        
        ((page++))
    done
    
    echo "$all_data"
}

# 获取所有群组
get_groups() {
    log_info "获取群组列表..."
    local groups=$(api_request "groups")
    local count=$(echo "$groups" | jq 'length')
    log_success "找到 $count 个群组"
    echo "$groups"
}

# 获取群组项目
get_group_projects() {
    local group_id="$1"
    local group_name="$2"
    log_info "获取群组 '$group_name' 的项目..."
    local projects=$(api_request "groups/${group_id}/projects")
    local count=$(echo "$projects" | jq 'length')
    log_success "群组 '$group_name' 有 $count 个项目"
    echo "$projects"
}

# 获取所有项目
get_all_projects() {
    log_info "获取所有项目..."
    local projects=$(api_request "projects")
    local count=$(echo "$projects" | jq 'length')
    log_success "找到 $count 个项目"
    echo "$projects"
}

# 克隆项目
clone_project() {
    local project_name="$1"
    local project_path="$2"
    local project_url="$3"
    local group_dir="$4"
    
    local project_dir="${group_dir}/${project_path}"
    
    if [[ -d "$project_dir" ]]; then
        log_warning "项目 '$project_name' 已存在，跳过克隆"
        return 0
    fi
    
    log_info "克隆项目: $project_name"
    
    # 构建带token的URL
    local token_url
    if [[ "$project_url" == *"@"* ]]; then
        # URL包含用户名，替换为token
        local protocol=$(echo "$project_url" | cut -d: -f1)
        local rest=$(echo "$project_url" | sed 's/.*@//')
        token_url="${protocol}://oauth2:${ACCESS_TOKEN}@${rest}"
    else
        # URL不包含用户名，添加token
        local protocol=$(echo "$project_url" | cut -d: -f1)
        local rest=$(echo "$project_url" | sed 's/.*:\/\///')
        token_url="${protocol}://oauth2:${ACCESS_TOKEN}@${rest}"
    fi
    
    # 克隆项目
    if git clone --mirror "$token_url" "$project_dir" 2>/dev/null; then
        log_success "成功克隆项目: $project_name"
        return 0
    else
        log_error "克隆项目 '$project_name' 失败"
        return 1
    fi
}

# 处理群组项目
process_group_projects() {
    local groups="$1"
    local group_count=$(echo "$groups" | jq 'length')
    
    for ((i=0; i<group_count; i++)); do
        local group=$(echo "$groups" | jq -r ".[$i]")
        local group_id=$(echo "$group" | jq -r '.id')
        local group_name=$(echo "$group" | jq -r '.name')
        local group_path=$(echo "$group" | jq -r '.path')
        
        log_info "处理群组: $group_name"
        
        # 创建群组目录
        local group_dir="${OUTPUT_DIR}/${group_path}"
        mkdir -p "$group_dir"
        
        # 获取群组项目
        local projects=$(get_group_projects "$group_id" "$group_name")
        local project_count=$(echo "$projects" | jq 'length')
        
        for ((j=0; j<project_count; j++)); do
            local project=$(echo "$projects" | jq -r ".[$j]")
            local project_name=$(echo "$project" | jq -r '.name')
            local project_path=$(echo "$project" | jq -r '.path')
            local project_url=$(echo "$project" | jq -r '.http_url_to_repo')
            
            clone_project "$project_name" "$project_path" "$project_url" "$group_dir"
        done
    done
}

# 处理未分组的项目
process_ungrouped_projects() {
    if [[ "$INCLUDE_UNGROUPED" == "false" ]]; then
        log_info "跳过未分组的项目"
        return
    fi
    
    log_info "处理未分组的项目..."
    
    # 获取所有项目
    local all_projects=$(get_all_projects)
    
    # 获取所有群组项目ID
    local groups=$(get_groups)
    local grouped_ids="[]"
    local group_count=$(echo "$groups" | jq 'length')
    
    for ((i=0; i<group_count; i++)); do
        local group_id=$(echo "$groups" | jq -r ".[$i].id")
        local group_projects=$(api_request "groups/${group_id}/projects")
        local project_ids=$(echo "$group_projects" | jq -r '.[].id')
        
        for project_id in $project_ids; do
            grouped_ids=$(echo "$grouped_ids" | jq --arg id "$project_id" '. += [$id]')
        done
    done
    
    # 找出未分组的项目
    local ungrouped_projects=$(echo "$all_projects" | jq --argjson grouped "$grouped_ids" \
        'map(select(.id | tostring | IN($grouped[] | tostring) | not))')
    
    local ungrouped_count=$(echo "$ungrouped_projects" | jq 'length')
    log_success "找到 $ungrouped_count 个未分组的项目"
    
    # 创建未分组目录
    local ungrouped_dir="${OUTPUT_DIR}/未分组"
    mkdir -p "$ungrouped_dir"
    
    # 克隆未分组的项目
    local project_count=$(echo "$ungrouped_projects" | jq 'length')
    for ((i=0; i<project_count; i++)); do
        local project=$(echo "$ungrouped_projects" | jq -r ".[$i]")
        local project_name=$(echo "$project" | jq -r '.name')
        local project_path=$(echo "$project" | jq -r '.path')
        local project_url=$(echo "$project" | jq -r '.http_url_to_repo')
        
        clone_project "$project_name" "$project_path" "$project_url" "$ungrouped_dir"
    done
}

# 主函数
main() {
    log_info "开始GitLab备份..."
    
    # 检查依赖
    check_dependencies
    
    # 解析参数
    parse_args "$@"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    # 获取所有群组
    local groups=$(get_groups)
    
    # 处理群组项目
    process_group_projects "$groups"
    
    # 处理未分组的项目
    process_ungrouped_projects
    
    log_success "GitLab备份完成!"
    log_info "备份目录: $OUTPUT_DIR"
}

# 运行主函数
main "$@"
