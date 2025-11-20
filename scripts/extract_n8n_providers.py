#!/usr/bin/env python3
"""
从 n8n 项目中提取提供商配置信息
包括：baseURL、apiBaseUrl、管理地址、图标路径等
"""

import os
import re
import json
from pathlib import Path
from typing import Dict, List, Optional

N8N_ROOT = Path("/Users/liuhuayao/dev/n8n-master")
AI_KEY_MANAGER_ROOT = Path("/Users/liuhuayao/dev/ai-key-manager")

# AI/ML 模型供应商关键词
AI_PROVIDER_KEYWORDS = [
    "OpenAI", "Anthropic", "Mistral", "Jina", "Perplexity", "Cohere", "Groq",
    "Google.*AI", "Azure.*AI", "AWS.*AI", "HuggingFace", "Gemini", "xAI",
    "Ollama", "DeepSeek", "MiniMax", "Zhipu", "Qwen", "Kimi", "Moonshot",
    "Baichuan", "Wenxin", "Nova", "ZeroOne", "Yi"
]

# 服务提供商关键词
SERVICE_PROVIDER_KEYWORDS = [
    "Supabase", "Notion", "N8n", "GitHub", "Figma", "Coze", "Dify"
]


def extract_base_url_from_file(file_path: Path) -> Optional[str]:
    """从文件中提取 baseURL"""
    try:
        content = file_path.read_text(encoding='utf-8')
        
        # 匹配 baseURL 模式
        patterns = [
            r"baseURL:\s*['\"]([^'\"]+)['\"]",
            r"baseURL:\s*`([^`]+)`",
            r"baseURL:\s*['\"]=([^'\"]+)['\"]",
            r"apiBaseUrl:\s*['\"]([^'\"]+)['\"]",
            r"apiBaseUrl:\s*`([^`]+)`",
            r"url:\s*['\"](https?://[^'\"]+)['\"]",
            r"url:\s*`(https?://[^`]+)`",
        ]
        
        for pattern in patterns:
            match = re.search(pattern, content)
            if match:
                url = match.group(1)
                # 清理表达式
                url = re.sub(r'=\{\{.*?\}\}', '', url)
                url = url.strip()
                if url.startswith('http'):
                    return url
        
        # 查找硬编码的 URL
        url_pattern = r'https?://[a-zA-Z0-9.-]+(?::[0-9]+)?(?:/[^\s\'"`]*)?'
        matches = re.findall(url_pattern, content)
        if matches:
            # 优先返回 API URL
            for url in matches:
                if 'api' in url.lower() or 'api.' in url:
                    return url
            return matches[0]
        
        return None
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return None


def extract_icon_path(node_dir: Path) -> Optional[str]:
    """提取节点图标路径"""
    icon_patterns = ['*.svg', '*.png']
    for pattern in icon_patterns:
        icons = list(node_dir.glob(pattern))
        if icons:
            # 优先返回 light 版本，否则返回第一个
            light_icon = next((i for i in icons if 'dark' not in i.name.lower()), None)
            if light_icon:
                return light_icon.name
            return icons[0].name
    return None


def extract_credential_info(cred_file: Path) -> Dict:
    """从凭证文件中提取信息"""
    info = {
        'name': None,
        'displayName': None,
        'baseUrl': None,
        'apiBaseUrl': None,
        'documentationUrl': None,
        'icon': None,
    }
    
    try:
        content = cred_file.read_text(encoding='utf-8')
        
        # 提取类名和显示名称
        name_match = re.search(r'name\s*=\s*[\'"]([^\'"]+)[\'"]', content)
        if name_match:
            info['name'] = name_match.group(1)
        
        display_match = re.search(r'displayName\s*=\s*[\'"]([^\'"]+)[\'"]', content)
        if display_match:
            info['displayName'] = display_match.group(1)
        
        # 提取 baseURL
        info['baseUrl'] = extract_base_url_from_file(cred_file)
        
        # 提取 apiBaseUrl
        api_base_match = re.search(r'apiBaseUrl:\s*[\'"]([^\'"]+)[\'"]', content)
        if api_base_match:
            info['apiBaseUrl'] = api_base_match.group(1)
        
        # 提取 documentationUrl
        doc_match = re.search(r'documentationUrl\s*=\s*[\'"]([^\'"]+)[\'"]', content)
        if doc_match:
            info['documentationUrl'] = doc_match.group(1)
        
        # 提取图标
        icon_match = re.search(r'icon.*?[\'"]([^\'"]+)[\'"]', content)
        if icon_match:
            info['icon'] = icon_match.group(1)
        
    except Exception as e:
        print(f"Error processing {cred_file}: {e}")
    
    return info


def extract_node_info(node_file: Path) -> Dict:
    """从节点文件中提取信息"""
    info = {
        'name': None,
        'displayName': None,
        'baseUrl': None,
        'icon': None,
    }
    
    try:
        content = node_file.read_text(encoding='utf-8')
        
        # 提取显示名称
        display_match = re.search(r'displayName:\s*[\'"]([^\'"]+)[\'"]', content)
        if display_match:
            info['displayName'] = display_match.group(1)
        
        # 提取 baseURL
        info['baseUrl'] = extract_base_url_from_file(node_file)
        
        # 提取图标
        icon_match = re.search(r'icon:\s*\{[^}]*light:\s*[\'"]file:([^\'"]+)[\'"]', content)
        if icon_match:
            info['icon'] = icon_match.group(1)
        
        # 从节点目录查找图标文件
        node_dir = node_file.parent
        icon_file = extract_icon_path(node_dir)
        if icon_file:
            info['icon'] = icon_file
        
    except Exception as e:
        print(f"Error processing {node_file}: {e}")
    
    return info


def scan_providers() -> List[Dict]:
    """扫描所有提供商"""
    providers = []
    
    # 扫描凭证文件
    cred_dir = N8N_ROOT / "packages/nodes-base/credentials"
    if cred_dir.exists():
        for cred_file in cred_dir.glob("*.credentials.ts"):
            # 检查是否是 AI/ML 或服务提供商
            file_name = cred_file.stem.lower()
            is_ai_provider = any(keyword.lower() in file_name for keyword in AI_PROVIDER_KEYWORDS)
            is_service_provider = any(keyword.lower() in file_name for keyword in SERVICE_PROVIDER_KEYWORDS)
            
            if is_ai_provider or is_service_provider:
                info = extract_credential_info(cred_file)
                info['type'] = 'credential'
                info['file'] = str(cred_file.relative_to(N8N_ROOT))
                providers.append(info)
    
    # 扫描节点文件
    nodes_dir = N8N_ROOT / "packages/nodes-base/nodes"
    if nodes_dir.exists():
        for node_file in nodes_dir.rglob("*.node.ts"):
            file_name = node_file.stem.lower()
            is_ai_provider = any(keyword.lower() in file_name for keyword in AI_PROVIDER_KEYWORDS)
            is_service_provider = any(keyword.lower() in file_name for keyword in SERVICE_PROVIDER_KEYWORDS)
            
            if is_ai_provider or is_service_provider:
                info = extract_node_info(node_file)
                info['type'] = 'node'
                info['file'] = str(node_file.relative_to(N8N_ROOT))
                providers.append(info)
    
    return providers


def main():
    """主函数"""
    print("开始扫描 n8n 提供商配置...")
    providers = scan_providers()
    
    print(f"\n找到 {len(providers)} 个提供商配置")
    
    # 保存结果
    output_file = AI_KEY_MANAGER_ROOT / "scripts/n8n_providers.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(providers, f, indent=2, ensure_ascii=False)
    
    print(f"\n结果已保存到: {output_file}")
    
    # 打印摘要
    print("\n提供商摘要:")
    for provider in providers:
        print(f"  - {provider.get('displayName', provider.get('name', 'Unknown'))}")
        if provider.get('baseUrl'):
            print(f"    BaseURL: {provider['baseUrl']}")
        if provider.get('icon'):
            print(f"    Icon: {provider['icon']}")


if __name__ == "__main__":
    main()

