#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GitLab项目备份脚本
通过管理员账号拉取GitLab上所有项目，包括所有分支，按群组分文件夹
"""

import os
import sys
import requests
import subprocess
import json
from pathlib import Path
from typing import List, Dict, Optional
import argparse
import logging
import time

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('gitlab_backup.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class GitLabBackup:
    def __init__(self, gitlab_url: str, access_token: str, output_dir: str = "gitlab_backup"):
        """
        初始化GitLab备份工具
        
        Args:
            gitlab_url: GitLab服务器URL (例如: https://gitlab.com)
            access_token: GitLab访问令牌
            output_dir: 输出目录
        """
        self.gitlab_url = gitlab_url.rstrip('/')
        self.access_token = access_token
        self.output_dir = Path(output_dir)
        self.api_url = f"{self.gitlab_url}/api/v4"
        self.headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        # 进度统计
        self.total_groups = 0
        self.total_projects = 0
        self.cloned_projects = 0
        self.skipped_projects = 0
        self.failed_projects = 0
        self.start_time = None
        
        # 创建输出目录
        self.output_dir.mkdir(exist_ok=True)
        
    def _make_request(self, endpoint: str, params: Dict = None) -> List[Dict]:
        """
        发送API请求
        
        Args:
            endpoint: API端点
            params: 请求参数
            
        Returns:
            API响应数据
        """
        url = f"{self.api_url}/{endpoint}"
        params = params or {}
        
        all_data = []
        page = 1
        
        while True:
            params['page'] = page
            params['per_page'] = 100
            
            try:
                response = requests.get(url, headers=self.headers, params=params)
                response.raise_for_status()
                
                data = response.json()
                if not data:  # 没有更多数据
                    break
                    
                all_data.extend(data)
                page += 1
                
                # 检查是否有下一页
                if len(data) < 100:
                    break
                    
            except requests.exceptions.RequestException as e:
                logger.error(f"API请求失败: {e}")
                break
                
        return all_data
    
    def get_groups(self) -> List[Dict]:
        """
        获取所有群组
        
        Returns:
            群组列表
        """
        logger.info("正在获取群组列表...")
        groups = self._make_request('groups')
        self.total_groups = len(groups)
        logger.info(f"找到 {self.total_groups} 个群组")
        return groups
    
    def get_projects(self, group_id: Optional[int] = None) -> List[Dict]:
        """
        获取项目列表
        
        Args:
            group_id: 群组ID，如果为None则获取所有项目
            
        Returns:
            项目列表
        """
        if group_id:
            logger.info(f"正在获取群组 {group_id} 的项目...")
            projects = self._make_request(f'groups/{group_id}/projects')
        else:
            logger.info("正在获取所有项目...")
            projects = self._make_request('projects')
            
        logger.info(f"找到 {len(projects)} 个项目")
        return projects
    
    def get_branches(self, project_id: int) -> List[Dict]:
        """
        获取项目的所有分支
        
        Args:
            project_id: 项目ID
            
        Returns:
            分支列表
        """
        branches = self._make_request(f'projects/{project_id}/repository/branches')
        return branches
    
    def clone_project(self, project: Dict, group_name: str = "其他", current: int = 0, total: int = 0) -> bool:
        """
        克隆项目及其所有分支
        
        Args:
            project: 项目信息
            group_name: 群组名称
            current: 当前项目序号
            total: 总项目数
            
        Returns:
            是否成功
        """
        project_name = project['name']
        project_path = project['path']
        project_url = project['http_url_to_repo']
        
        # 创建群组目录
        group_dir = self.output_dir / group_name
        group_dir.mkdir(exist_ok=True)
        
        # 项目目录
        project_dir = group_dir / project_path
        
        # 显示进度
        if total > 0:
            progress = f"[{current}/{total}] "
        else:
            progress = ""
        
        if project_dir.exists():
            logger.info(f"{progress}项目 {project_name} 已存在，跳过克隆")
            self.skipped_projects += 1
            return True
            
        try:
            # 克隆项目
            logger.info(f"{progress}正在克隆项目: {project_name}")
            
            # 替换URL中的用户名和密码为访问令牌
            if '@' in project_url:
                # 如果URL包含用户名，替换为token
                url_parts = project_url.split('@')
                token_url = f"{url_parts[0].split('://')[0]}://oauth2:{self.access_token}@{url_parts[1]}"
            else:
                # 如果URL不包含用户名，添加token
                url_parts = project_url.split('://')
                token_url = f"{url_parts[0]}://oauth2:{self.access_token}@{url_parts[1]}"

            token_url = token_url.replace("gitlab.navclips.com", "47.107.158.127")
            
            # 执行git clone
            result = subprocess.run(
                ['git', 'clone', '--mirror', token_url, str(project_dir)],
                capture_output=True,
                text=True,
                cwd=str(group_dir)
            )
            
            if result.returncode != 0:
                logger.error(f"{progress}克隆项目 {project_name} 失败: {result.stderr}")
                self.failed_projects += 1
                return False
                
            logger.info(f"{progress}成功克隆项目: {project_name}")
            self.cloned_projects += 1
            return True
            
        except Exception as e:
            logger.error(f"{progress}克隆项目 {project_name} 时发生错误: {e}")
            self.failed_projects += 1
            return False
    
    def backup_all(self, include_ungrouped: bool = True):
        """
        备份所有项目
        
        Args:
            include_ungrouped: 是否包含未分组的项目
        """
        self.start_time = time.time()
        logger.info("开始GitLab备份...")
        
        # 获取所有群组
        groups = self.get_groups()
        group_dict = {group['id']: group for group in groups}
        
        # 统计总项目数
        total_projects = 0
        for group in groups:
            group_projects = self.get_projects(group['id'])
            total_projects += len(group_projects)
        
        if include_ungrouped:
            all_projects = self.get_projects()
            grouped_project_ids = set()
            for group in groups:
                group_projects = self.get_projects(group['id'])
                grouped_project_ids.update(project['id'] for project in group_projects)
            ungrouped_projects = [p for p in all_projects if p['id'] not in grouped_project_ids]
            total_projects += len(ungrouped_projects)
        
        self.total_projects = total_projects
        logger.info(f"总计需要处理 {self.total_projects} 个项目")
        
        # 备份群组项目
        current_project = 0
        for group in groups:
            group_id = group['id']
            group_name = group['name']
            group_path = group['path']
            
            logger.info(f"处理群组: {group_name}")
            
            # 获取群组项目
            projects = self.get_projects(group_id)
            
            for project in projects:
                current_project += 1
                self.clone_project(project, group_path, current_project, self.total_projects)
        
        # 备份未分组的项目
        if include_ungrouped:
            logger.info("处理未分组的项目...")
            all_projects = self.get_projects()
            
            # 找出未分组的项目
            grouped_project_ids = set()
            for group in groups:
                group_projects = self.get_projects(group['id'])
                grouped_project_ids.update(project['id'] for project in group_projects)
            
            ungrouped_projects = [p for p in all_projects if p['id'] not in grouped_project_ids]
            
            logger.info(f"找到 {len(ungrouped_projects)} 个未分组的项目")
            
            for project in ungrouped_projects:
                current_project += 1
                self.clone_project(project, "未分组", current_project, self.total_projects)
        
        # 显示最终统计信息
        self._show_final_stats()
        
    def _show_final_stats(self):
        """显示最终统计信息"""
        end_time = time.time()
        duration = end_time - self.start_time
        
        logger.info("=" * 60)
        logger.info("GitLab备份完成!")
        logger.info(f"总群组数: {self.total_groups}")
        logger.info(f"总项目数: {self.total_projects}")
        logger.info(f"成功克隆: {self.cloned_projects}")
        logger.info(f"跳过项目: {self.skipped_projects}")
        logger.info(f"失败项目: {self.failed_projects}")
        logger.info(f"总耗时: {duration:.2f} 秒")
        logger.info(f"备份目录: {self.output_dir}")
        logger.info("=" * 60)

def main():
    parser = argparse.ArgumentParser(description='GitLab项目备份工具')
    parser.add_argument('--url', required=True, help='GitLab服务器URL (例如: https://gitlab.com)')
    parser.add_argument('--token', required=True, help='GitLab访问令牌')
    parser.add_argument('--output', default='gitlab_backup', help='输出目录 (默认: gitlab_backup)')
    parser.add_argument('--no-ungrouped', action='store_true', help='不包含未分组的项目')
    
    args = parser.parse_args()
    
    # 检查git是否安装
    try:
        subprocess.run(['git', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        logger.error("Git未安装或不在PATH中")
        sys.exit(1)
    
    # 创建备份工具实例
    backup_tool = GitLabBackup(
        gitlab_url=args.url,
        access_token=args.token,
        output_dir=args.output
    )
    
    # 开始备份
    backup_tool.backup_all(include_ungrouped=not args.no_ungrouped)

if __name__ == "__main__":
    main()
