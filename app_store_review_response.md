# App Store 审核回复 - 地区限制功能说明

## 尊敬的 App Store 审核团队：

### 中文版本

亲爱的审核团队：

感谢您对我们应用 "密枢" 的审核。我们已经认真研究了您关于应用在中国大陆地区可用性的反馈，并已实施了严格的强制地区限制功能，完全符合相关法律法规要求。

**功能实现详情：**

1. **强制地区检测和限制机制**
   - 应用启动时会自动检测用户所在地区（通过时区CST、系统语言环境和LANG环境变量等多重方式）
   - **对中国大陆地区用户强制开启地区过滤功能，无法手动关闭**
   - **对中国大陆地区用户完全隐藏地区过滤设置开关**
   - 这些限制是为了严格遵守《互联网信息服务深度合成管理规定》等相关法律法规

2. **彻底屏蔽受限AI服务**
   - 强制过滤以下在中国大陆地区受限的AI服务提供商：
     - OpenAI (包括所有OpenAI相关服务)
     - Azure OpenAI
     - ChatGPT
   - 在新建密钥界面，新建模板列表中完全不显示上述受限服务
   - 在平台预设配置中自动过滤掉受限服务的管理地址和API地址
   - **保留OpenAI兼容格式的服务** - 这些使用标准API协议的国内AI服务不受限制
     - OpenAI兼容格式是一种通用的API协议标准，许多国内AI服务商（如百度千帆、腾讯云、阿里云等）采用此格式提供服务
     - 这些服务本身与OpenAI无关，仅使用相同的API调用规范以提高兼容性和易用性

3. **技术实现方式**
   - 使用SharedPreferences本地存储地区检测结果
   - 客户端本地实现所有过滤逻辑，无服务器端内容审查
   - 地区检测结果每次启动时重新验证，确保合规性
   - 过滤逻辑贯穿整个应用：平台注册表、预设配置、新建密钥界面等

4. **用户体验设计**
   - 中国大陆地区用户不会看到任何受限服务的选项
   - 非中国大陆地区用户可以正常使用所有功能
   - 应用会根据地区自动调整可用功能，无需用户手动配置

我们相信这些强制性的地区限制措施能够完全满足App Store的审核要求，确保应用在中国大陆地区的合规运营。如果您需要查看具体的代码实现或有任何疑问，请随时联系我们。

谢谢您的理解和支持！

**密枢开发团队**

---

### English Version

Dear App Store Review Team:

Thank you for reviewing our app "密枢". We have carefully studied your feedback regarding app availability in mainland China and have implemented strict mandatory regional restriction features that fully comply with relevant laws and regulations.

**Feature Implementation Details:**

1. **Mandatory Region Detection and Restriction Mechanism**
   - The app automatically detects the user's region upon startup (using timezone CST, system locale, and LANG environment variables)
   - **Forces regional filtering ON for mainland China users, cannot be manually disabled**
   - **Completely hides the regional filtering toggle from mainland China users**
   - These restrictions strictly comply with regulations such as the "Provisions on the Administration of Internet Information Service Deep Synthesis"

2. **Complete Blocking of Restricted AI Services**
   - Mandatory filtering of the following AI service providers restricted in mainland China:
     - OpenAI (all OpenAI-related services)
     - Azure OpenAI
     - ChatGPT
   - Completely removes these restricted services from the new key creation template list
   - Automatically filters out management URLs and API addresses for restricted services in platform presets
   - **Preserves OpenAI-compatible services** - Domestic AI services using standard API protocols remain unrestricted
     - OpenAI-compatible format is a universal API protocol standard adopted by many domestic AI providers (such as Baidu Qianfan, Tencent Cloud, Alibaba Cloud, etc.)
     - These services are not affiliated with OpenAI and only use the same API calling specifications to improve compatibility and usability

3. **Technical Implementation**
   - Uses SharedPreferences for local storage of region detection results
   - All filtering logic implemented client-side, no server-side content moderation
   - Region detection re-verified on every app launch to ensure compliance
   - Filtering logic integrated throughout the app: platform registry, presets, new key creation interface, etc.

4. **User Experience Design**
   - Mainland China users will not see any options for restricted services
   - Non-mainland China users can use all features normally
   - The app automatically adjusts available features based on region, no manual configuration required

We believe these mandatory regional restrictions fully meet App Store review requirements and ensure compliant operation in mainland China. If you need to review the specific code implementation or have any questions, please don't hesitate to contact us.

Thank you for your understanding and support!

**密枢 Development Team**

---

### 技术实现代码片段

```dart
/// 地区过滤服务核心实现 - 强制限制版本
class RegionFilterService {
  /// 检测是否为中国大陆地区
  static Future<bool> _detectChinaRegion() async {
    // 1. 检查时区 (CST)
    final timezone = DateTime.now().timeZoneName.toLowerCase();
    if (timezone.contains('cst')) {
      return true;
    }

    // 2. 检查系统语言环境
    final locale = Platform.localeName.toLowerCase();
    if (locale.startsWith('zh_cn')) {
      return true;
    }

    // 3. 检查环境变量
    final lang = Platform.environment['LANG']?.toLowerCase() ?? '';
    if (lang.contains('zh_cn')) {
      return true;
    }

    return false;
  }

  /// 检查地区过滤是否启用 - 中国大陆地区强制返回true
  static Future<bool> isChinaRegionFilterEnabled() async {
    final isChina = await isInChinaRegion();
    if (isChina) {
      // 中国大陆地区强制开启地区过滤，屏蔽OpenAI相关服务
      // 但保留OpenAI兼容格式的国内AI服务（如百度、腾讯、阿里云等）
      // 因为兼容格式仅是API协议标准，不等同于OpenAI服务本身
      return true;
    }
    // 非中国大陆地区关闭地区过滤
    return false;
  }

  /// 检查是否应该显示地区过滤设置 - 中国大陆地区隐藏
  static Future<bool> shouldShowRegionFilterSetting() async {
    // 中国大陆地区强制开启地区过滤，隐藏设置项
    // 非中国大陆地区显示设置项，让用户可以选择
    return !(await isInChinaRegion());
  }

  /// 初始化地区检测 - 强制设置逻辑
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 每次启动都重新检测地区
    final isChina = await _detectChinaRegion();

    // 中国大陆地区强制开启地区过滤，非中国大陆地区关闭
    final shouldEnableFilter = isChina;
    await prefs.setBool(_chinaRegionKey, shouldEnableFilter);

    print('🔒 RegionFilter: 强制设置地区过滤 - ${shouldEnableFilter ? '开启（中国大陆地区合规要求）' : '关闭（非中国大陆地区）'}');
  }
}
```

### 受限平台列表（中国大陆地区完全屏蔽）
- OpenAI (openAI)
- Azure OpenAI (azureOpenAI)
- ChatGPT (chatgpt)

**保留的服务：**
- OpenAI兼容服务 (openai-compatible) - 国内AI服务使用标准API协议，不受限制
  - 这些服务包括：百度千帆、腾讯云、阿里云、字节跳动、零一万物、百川智能等国内AI服务商
  - 它们采用OpenAI兼容格式仅为提高API兼容性，与OpenAI服务本身无关

**屏蔽范围：**
- 新建密钥模板列表中完全不显示受限平台
- 平台预设配置中自动过滤受限平台的管理地址和API地址
- 所有相关元数据和功能在检测到中国大陆地区时自动隐藏

---

*最后更新时间：2025年12月24日*
