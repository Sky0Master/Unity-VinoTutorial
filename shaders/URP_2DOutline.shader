Shader "Unlit/URP_2DOutline" 
{
    Properties
    {
        // 主纹理属性（贴图槽）
        _MainTex ("Texture", 2D) = "white" {}
        // 轮廓颜色属性（RGBA格式）
        _OutlineColor ("Outline Color", Color) = (1,1,1,1)
        // 轮廓粗细（范围限制防止过大的偏移）
        _OutlineThickness ("Outline Thickness", Range(0, 0.1)) = 0.01
        // 功能开关：是否采样额外纹理（可用于扩展功能）
        [Toggle(_SAMPLE_ADDITIONAL_TEXTURES)] _SampleAdditionalTextures ("Sample Additional Textures", Float) = 0.0
    }

    SubShader
    {
        // 渲染标签配置
        Tags { 
            "RenderType"="Transparent"   // 标识为透明物体类型
            "Queue"="Transparent"        // 使用透明物体渲染队列（后渲染）
            "RenderPipeline"="UniversalRenderPipeline" // 指定URP管线
        }
        
        Pass
        {
            // 设置透明混合模式（标准Alpha混合）
            Blend SrcAlpha OneMinusSrcAlpha 

            HLSLPROGRAM
            // 着色器编译指令
            #pragma vertex vert    // 指定顶点着色器
            #pragma fragment frag  // 指定片段着色器
            #pragma shader_feature _SAMPLE_ADDITIONAL_TEXTURES // 条件编译功能开关

            // 包含URP核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 顶点着色器输入结构（从Mesh数据获取）
            struct Attributes
            {
                float4 positionOS : POSITION; // 物体空间顶点位置
                float2 uv : TEXCOORD0;        // 第一套UV坐标
                float4 color : COLOR;         // 顶点颜色（可用于色相调整）
            };

            // 顶点到片段的数据传递结构
            struct Varyings
            {
                float4 positionCS : SV_POSITION; // 裁剪空间位置（必须）
                float2 uv : TEXCOORD0;           // 传递UV坐标
                float4 color : COLOR;            // 传递顶点颜色
            };

            // 声明Shader属性对应的变量
            sampler2D _MainTex;        // 主纹理采样器
            float4 _MainTex_ST;        // 纹理的缩放偏移参数（ST = Scale/Translate）
            half4 _OutlineColor;       // 轮廓颜色（half精度足够）
            half _OutlineThickness;    // 轮廓粗细值

            // 顶点着色器
            Varyings vert (Attributes input)
            {
                Varyings output;
                // 将物体空间坐标转换到裁剪空间（核心变换）
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                // 应用纹理的缩放和偏移到UV坐标
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                // 传递顶点颜色（未使用时可优化移除）
                output.color = input.color;
                return output;
            }

            // 片段着色器
            half4 frag (Varyings input) : SV_Target
            {
                // 采样主纹理颜色（默认过滤模式）
                half4 mainColor = tex2D(_MainTex, input.uv);

                /* 提前终止优化：当主纹理完全透明时直接丢弃片段
                 * 优点：
                 * 1. 节省后续计算开销
                 * 2. 避免透明边缘出现异常轮廓
                 */
                if (mainColor.a <= 0.0)
                {
                    discard; // 丢弃当前片段（不写入任何缓冲区）
                }

                //--- 轮廓计算核心逻辑 Begin ---//
                // 计算采样偏移量（基于UV空间的比例）
                // 注意：当纹理Wrap Mode为Clamp时，边缘采样可能不正确
                half2 offset = _OutlineThickness;

                /* 四方向采样策略（基础实现）
                 * 改进建议：
                 * 1. 可升级为8方向采样减少锯齿
                 * 2. 使用Sobel算子检测边缘
                 */
                half4 up    = tex2D(_MainTex, input.uv + half2(0, offset.y));    // 上方采样
                half4 down  = tex2D(_MainTex, input.uv - half2(0, offset.y));   // 下方采样
                half4 left  = tex2D(_MainTex, input.uv - half2(offset.x, 0));  // 左侧采样
                half4 right = tex2D(_MainTex, input.uv + half2(offset.x, 0));   // 右侧采样

                /* 轮廓透明度计算逻辑：
                 * 当前像素与周围像素的Alpha差值决定轮廓强度
                 * saturate限制差值在0-1范围
                 * max取四方向中的最大值作为最终轮廓强度
                 */
                half outlineAlpha = 0.0;
                outlineAlpha = max(outlineAlpha, saturate(mainColor.a - up.a));    // 上边缘
                outlineAlpha = max(outlineAlpha, saturate(mainColor.a - down.a));  // 下边缘
                outlineAlpha = max(outlineAlpha, saturate(mainColor.a - left.a));  // 左边缘
                outlineAlpha = max(outlineAlpha, saturate(mainColor.a - right.a)); // 右边缘

                //--- 颜色合成阶段 ---//
                /* 颜色混合逻辑：
                 * 使用lerp在原始颜色和轮廓颜色之间插值
                 * outlineAlpha为0时显示原色，1时显示轮廓色
                 */
                half4 finalColor = lerp(mainColor, _OutlineColor, outlineAlpha);

                /* Alpha通道混合公式解析：
                 * 原始Alpha * (1 - outlineAlpha) + 轮廓Alpha * outlineAlpha
                 * 但轮廓Alpha始终为1（_OutlineColor.a默认为1）
                 * 简化为：min(mainColor.a, 1.0 - outlineAlpha + mainColor.a * outlineAlpha)
                 * 确保轮廓区域不会超过原始透明度
                 */
                finalColor.a = min(mainColor.a, 1.0 - outlineAlpha + mainColor.a * outlineAlpha);
                finalColor.a = saturate(finalColor.a); // 保险措施：限制到合法范围

                return finalColor;
            }
            ENDHLSL
        }
    }
}
