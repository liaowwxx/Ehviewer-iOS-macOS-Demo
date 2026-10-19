#if os(macOS)
enum TranslationParameterLabels {
    static let values = [
        "device": "计算设备", "model": "模型", "language": "识别语言", "precision": "计算精度",
        "inpaint_size": "修复尺寸", "detect_size": "检测尺寸", "delay": "请求间隔（秒）",
        "name": "配置名称", "backend": "API 协议", "base_url": "API 地址", "api_key": "API Key",
        "vision_model": "OCR / 视觉模型", "image_model": "图像修复模型", "image_base_url": "图像 API 地址",
        "support_text": "用于文字翻译", "support_vision": "用于视觉识别", "support_image": "用于图像修复",
        "require_api_key": "需要 API Key", "max_tokens": "最大输出 Token", "temperature": "采样温度",
        "top_p": "Top P", "thinking_level": "推理强度", "prompt": "翻译提示词", "vision_prompt": "OCR 提示词",
        "vision_detail_level": "图像细节", "llm_glossary_mode": "术语使用范围", "ocr_text_postprocess": "OCR 文字处理",
        "image_prompt": "图像修复提示词", "json_schema_response_format": "结构化 JSON 输出", "low_vram_mode": "低显存模式",
        "font_family": "字体", "font_size": "字号", "stroke_width": "描边宽度", "vertical": "竖排", "line_spacing": "行间距",
        "translate_context": "翻译上下文", "llm_translate_context": "LLM 上下文", "llm_prior_context_token_budget": "历史上下文 Token 预算",
        "llm_glossary_path": "术语表路径", "llm_translate_vision": "翻译时使用图像", "llm_translate_summary_memory": "跨页摘要记忆",
        "ocr_llm_page_level": "按整页识别", "ocr_font_detect": "检测字体", "imgsave_ext": "输出格式", "imgsave_quality": "输出质量",
        "let_family_flag": "字体来源", "let_fntsize_flag": "字号来源",
        "let_writing_mode_flag": "排版方向来源", "frequency_penalty": "频率惩罚", "presence_penalty": "重复惩罚",
        "font size multiplier": "字号倍率", "font size max": "字号上限", "font size min": "字号下限", "mask dilate size": "掩膜扩张",
        "proxy": "代理地址", "retry attempts": "重试次数", "retry timeout": "重试间隔（秒）", "max requests per minute": "每分钟请求上限"
    ]
}
#endif
