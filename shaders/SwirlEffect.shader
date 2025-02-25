Shader "Unlit/SwirlEffect"
{
    Properties {
        _MainTex ("Base Texture", 2D) = "white" {}    // 基础纹理输入,用于最终颜色输出
        _Angle ("Rotation Angle", Range(0,10)) = 2    // 控制旋转强度的参数, Range(0,10)限制调节范围避免过度扭曲
        _Radius ("Effect Radius", Range(0,1)) = 0.5   // 效果作用半径，控制漩涡中心到边缘的衰减范围
    }
    SubShader
    {
        Tags { 
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "RenderPipeline"="UniversalPipeline"
        }
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha // 标准透明度混合
            //AlphaToMask On                  // 启用Alpha抗锯齿
            HLSLPROGRAM //使用URP标准的HLSL语法
            #pragma vertex vert // 声明顶点着色器
            #pragma fragment frag  // 声明片段着色器
            
            //#pragma multi_compile_fog //开启雾效支持
            
            //URP专用
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes { //输入数据结构 (URP命名规范)
                float4 positionOS : POSITION; //物体空间的顶点坐标
                float2 uv : TEXCOORD0;  //初始纹理坐标
            };

            struct Varyings {   //输出数据结构 (URP命名规范)
                float4 positionCS : SV_POSITION; //裁剪空间坐标(SV_前缀)
                float2 uv : TEXCOORD0;  //传递纹理坐标
            };

            TEXTURE2D(_MainTex);    //在HLSL中，TEXTURE2D是一个宏，用于声明纹理资源, 这行代码告诉Shader存在一个名为_MainTex的2D纹理，供后续采样使用
            SAMPLER(sampler_MainTex); //SAMPLER宏声明采样器状态，与纹理绑定。URP中，纹理和采样器通常是分开的，这样可以更灵活地重用采样器设置
            float _Angle;   //自定义的属性，在Properties块中声明后，需要在HLSL代码中再次声明，以便在着色器中使用. 这样可以在Properties和HLSL中同步变量，确保参数传递正确
            float _Radius;

            Varyings vert(Attributes IN) {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz); // URP坐标变换
                OUT.uv = IN.uv;   // 直接传递UV
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target {
                // 计算中心偏移
                float2 centerOffset = IN.uv - float2(0.5,0.5);
                float distance = length(centerOffset);

                if(distance > _Radius)
                    return half4(0,0,0,0); // 距离小于半径不渲染
                
                // 动态旋转计算
                float rotation = _Angle * saturate(1 - distance/_Radius); //基于自定义半径的衰减计算
                float sinRot, cosRot;   
                sincos(rotation, sinRot, cosRot); //性能优化，同时计算旋转角度的sin和cos而不是分开计算
                
                // UV变换矩阵
                float2x2 rotMatrix = float2x2(cosRot, -sinRot, sinRot, cosRot); //旋转矩阵构造
                float2 distortedUV = mul(rotMatrix, centerOffset) + 0.5;    //应用矩阵变换

                // 采样纹理
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, distortedUV); //使用变换后的uv坐标去采样纹理
                
                // 边缘淡化
                float fade = smoothstep(_Radius, _Radius * 0.5, distance); //边缘过渡优化
                return half4(color.rgb, color.a * fade);    //透明度混合
            }
            ENDHLSL
        }
    }
}
