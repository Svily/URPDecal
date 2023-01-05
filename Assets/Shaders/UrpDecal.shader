// see README here: 
// github.com/ColinLeung-NiloCat/UnityURPUnlitScreenSpaceDecalShader

Shader "Universal Render Pipeline/NiloCat Extension/Screen Space Decal/Unlit"
{
    Properties
    {
        [Header(Basic)]
        _MainTex("Texture", 2D) = "white" {}
        [HDR]_Color("_Color (default = 1,1,1,1)", color) = (1,1,1,1)

        [Header(Blending)]
        // BlendMode官方手册：https://docs.unity3d.com/ScriptReference/Rendering.BlendMode.html
        // 混合模式
        [Enum(UnityEngine.Rendering.BlendMode)]_SrcBlend("_SrcBlend (default = SrcAlpha)", Float) = 5 // 5 = SrcAlpha
        [Enum(UnityEngine.Rendering.BlendMode)]_DstBlend("_DstBlend (default = OneMinusSrcAlpha)", Float) = 10 // 10 = OneMinusSrcAlpha

        [Header(Alpha remap(extra alpha control))]
        _AlphaRemap("_AlphaRemap (default = 1,0,0,0) _____alpha will first mul x, then add y    (zw unused)", vector) = (1,0,0,0)

        [Header(Prevent Side Stretching(Compare projection direction with scene normal and Discard if needed))]
        [Toggle(_ProjectionAngleDiscardEnable)] _ProjectionAngleDiscardEnable("_ProjectionAngleDiscardEnable (default = off)", float) = 0
        _ProjectionAngleDiscardThreshold("_ProjectionAngleDiscardThreshold (default = 0)", range(-1,1)) = 0

        [Header(Mul alpha to rgb)]
        [Toggle]_MulAlphaToRGB("_MulAlphaToRGB (default = off)", Float) = 0

        [Header(Ignore texture wrap mode setting)]
        [Toggle(_FracUVEnable)] _FracUVEnable("_FracUVEnable (default = off)", Float) = 0

        //====================================== 在常规的用例中，通常可以忽略下面这些设置 =====================================================================
        [Header(Stencil Masking)]
        // https://docs.unity3d.com/ScriptReference/Rendering.CompareFunction.html
        _StencilRef("_StencilRef", Float) = 0
        [Enum(UnityEngine.Rendering.CompareFunction)]_StencilComp("_StencilComp (default = Disable) _____Set to NotEqual if you want to mask by specific _StencilRef value, else set to Disable", Float) = 0 //0 = disable

        [Header(ZTest)]
        // https://docs.unity3d.com/ScriptReference/Rendering.CompareFunction.html
        // 默认Disable, 因为我们需要确保即使相机进入贴花立方体体积，贴花渲染也正确，尽管默认禁用ZTest将阻止EarlyZ(不利于GPU性能)
        [Enum(UnityEngine.Rendering.CompareFunction)]_ZTest("_ZTest (default = Disable) _____to improve GPU performance, Set to LessEqual if camera never goes into cube volume, else set to Disable", Float) = 0 //0 = disable

        [Header(Cull)]
        // CullMode官方手册: https://docs.unity3d.com/ScriptReference/Rendering.CullMode.html
        // 默认为Front, 因为我们需要确保即使相机进入贴花立方体体积，贴花渲染也正确
        [Enum(UnityEngine.Rendering.CullMode)]_Cull("_Cull (default = Front) _____to improve GPU performance, Set to Back if camera never goes into cube volume, else set to Front", Float) = 1 //1 = Front

        [Header(Unity Fog)]
        [Toggle(_UnityFogEnable)] _UnityFogEnable("_UnityFogEnable (default = on)", Float) = 1

        [Header(Support Orthographic camera)]
        [Toggle(_SupportOrthographicCamera)] _SupportOrthographicCamera("_SupportOrthographicCamera (default = off)", Float) = 0
    }

    SubShader
    {
        // 关于tags的内容可以查阅官网手册：https://docs.unity3d.com/Manual/SL-SubShaderTags.html
        // 为了避免渲染顺序问题, Queue必须 >= 2501, 它位于透明队列中
        // 在透明队列中，Unity总是从后到前渲染
        // 2500以下是不透明物体队列，会进行渲染优化，比如被遮住的就剔除掉不进行渲染
        // 2500以上是透明物体队列，它会根据距离摄像机的距离进行排序
        // 从最远的开始渲染，到最近的结束
        // 天空盒被渲染在所有不透明和透明物体之间
        // "Queue" = "Transparent-499" 即 "Queue" = "2501", 使得它早于所有透明物体进行渲染
        Tags { "RenderType" = "Overlay" "Queue" = "Transparent-499" "DisableBatching" = "True" }

        Pass
        {
            Stencil
            {
                Ref[_StencilRef]
                Comp[_StencilComp]
            }

            Cull[_Cull]
            ZTest[_ZTest]

            // 为了支持透明度混合，关闭深度写入
            ZWrite off
            Blend[_SrcBlend][_DstBlend]

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            // 雾效
            #pragma multi_compile_fog

            // 为了使用 ddx() & ddy()
            #pragma target 3.0

            #pragma shader_feature_local_fragment _ProjectionAngleDiscardEnable
            #pragma shader_feature_local _UnityFogEnable
            #pragma shader_feature_local_fragment _FracUVEnable
            #pragma shader_feature_local_fragment _SupportOrthographicCamera

            // 所有URP渲染管线的shader都必须引入这个Core.hlsl
            // 它包含内置shader的变量，比如光照相关的变量，文档：https://docs.unity3d.com/Manual/SL-UnityShaderVariables.html
            // 同时它也包含很多工具方法
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                // 模型空间下的坐标，OS: Object Space
                float3 positionOS : POSITION;
            };

            struct v2f
            {
                // 齐次裁剪空间坐标，CS: Clip Space
                float4 positionCS : SV_POSITION;
                // 屏幕坐标
                float4 screenPos : TEXCOORD0;
                // xyz分量: 表示viewRayOS, 即模型空间 (Object Space)下的摄像机到顶点的射线
                // w分量: 拷贝positionVS.z的值，即观察空间 (View Space) 下的顶点坐标的z分量
                float4 viewRayOS : TEXCOORD1; 
                // rgb分量：表示模型空间下的摄像机坐标，
                // a分量：表示雾的强度
                float4 cameraPosOSAndFogFactor : TEXCOORD2;
            };

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;

            // 支持SRP Batcher
            CBUFFER_START(UnityPerMaterial)               
                float4 _MainTex_ST;
                float _ProjectionAngleDiscardThreshold;
                half4 _Color;
                half2 _AlphaRemap;
                half _MulAlphaToRGB;
            CBUFFER_END

            // 顶点着色器
            v2f vert(appdata input)
            {
                v2f o;

                // VertexPositionInputs包含多个空间坐标系中的位置(world, view, homogeneous clip space, ndc)
                // Unity编译器将剥离所有未使用的引用 （比如你没有使用view space）
                // 因此，这种结构具有更大的灵活性，无需额外的成本
                VertexPositionInputs vertexPositionInput = GetVertexPositionInputs(input.positionOS);
                // 得到齐次裁剪空间 (clip space) 下的坐标
                o.positionCS = vertexPositionInput.positionCS;

                // Unity雾效
#if _UnityFogEnable
                o.cameraPosOSAndFogFactor.a = ComputeFogFactor(o.positionCS.z);
#else
                o.cameraPosOSAndFogFactor.a = 0;
#endif

                // 准备深度纹理的屏幕空间UV
                o.screenPos = ComputeScreenPos(o.positionCS);

                // 观察空间 (view space) 坐标，即在观察空间中摄像机到顶点的射线向量
                float3 viewRay = vertexPositionInput.positionVS;

                // [注意，这一步很关键]
                //=========================================================
                // viewRay除以z分量必须在片元着色器中执行，不能在顶点着色器中执行! (由于光栅化变化插值的透视校正)
                // 我们先把viewRay.z存到o.viewRayOS.w中，等到片元着色器阶段在进行处理
                o.viewRayOS.w = viewRay.z;
                //=========================================================

                // unity的相机空间是右手坐标系(z轴负方向指向屏幕)，我们希望片段着色器中z射线是正的，所以取反
                viewRay *= -1;

                // 观察空间到模型空间的变换矩阵
                float4x4 ViewToObjectMatrix = mul(UNITY_MATRIX_I_M, UNITY_MATRIX_I_V);

                // 观察空间 (view space) 转模型空间 (object space) 
                o.viewRayOS.xyz = mul((float3x3)ViewToObjectMatrix, viewRay);
                // 模型空间下摄像机的坐标
                o.cameraPosOSAndFogFactor.xyz = mul(ViewToObjectMatrix, float4(0,0,0,1)).xyz; 

                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                // [注意，这一步很关键]
                //========================================================================
                // 去齐次
                i.viewRayOS.xyz /= i.viewRayOS.w;
                //========================================================================

                // 深度纹理的UV
                float2 screenSpaceUV = i.screenPos.xy / i.screenPos.w;
                // 对深度纹理进行采样，得到深度信息
                float sceneRawDepth = tex2D(_CameraDepthTexture, screenSpaceUV).r;

                float3 decalSpaceScenePos;

// 正交相机
#if _SupportOrthographicCamera
                // 我们必须支持正交和透视两种投影
                // unity_OrthoParams：
                //      unity_OrthoParams是内置着色器遍历，存储的信息如下：
                //      x 是正交摄像机的宽度，y 是正交摄像机的高度，z 未使用，w 在摄像机为正交模式时是 1.0，而在摄像机为透视模式时是 0.0。
                //      更多的内置着色器遍历可查看官方手册: https://docs.unity.cn/cn/2019.4/Manual/SL-UnityShaderVariables.html
                // (这里要放 UNITY_BRANCH 吗?) 我决定不放，原因看这里： https://forum.unity.com/threads/correct-use-of-unity_branch.476804/
                if(unity_OrthoParams.w)
                {
                    // 如果是正交摄像机, _CameraDepthTexture在[0,1]内线性存储场景深度
                    #if defined(UNITY_REVERSED_Z)
                    // 如果platform使用反向深度，要使用1-depth
                    // https://docs.unity3d.com/Manual/SL-PlatformDifferences.html
                    sceneRawDepth = 1-sceneRawDepth;
                    #endif
 
                    // 使用简单的lerp插值： lerp(near,far, [0,1] linear depth)， 得到观察空间 (view space)的深度信息               
                    float sceneDepthVS = lerp(_ProjectionParams.y, _ProjectionParams.z, sceneRawDepth);


                    // 投影
				    float2 viewRayEndPosVS_xy = float2(unity_OrthoParams.xy * (i.screenPos.xy - 0.5) * 2 /* 裁剪空间 */);  
                    // 构建观察空间坐标
				    float4 vposOrtho = float4(viewRayEndPosVS_xy, -sceneDepthVS, 1);                                            
                    // 观察空间转世界空间
				    float3 wposOrtho = mul(UNITY_MATRIX_I_V, vposOrtho).xyz;                                                 
                    //----------------------------------------------------------------------------

                    // 世界空间转模型空间 (贴花空间)
                    decalSpaceScenePos = mul(GetWorldToObjectMatrix(), float4(wposOrtho, 1)).xyz;
                }
                else
                {
#endif
                    // 如果是透视相机，LinearEyeDepth将为用户处理一切
                    // 记住，我们不能使用LinearEyeDepth处理正交相机!
                    // _ZBufferParams: 
                    //      用于线性化 Z 缓冲区值。x 是 (1-远/近)，y 是 (远/近)，z 是 (x/远)，w 是 (y/远)。
                    float sceneDepthVS = LinearEyeDepth(sceneRawDepth, _ZBufferParams);

                    // 在任何空间中，场景深度 = rayStartPos + rayDir * rayLength
                    // 这里所有的数据在 模型空间 (object space) 或 贴花空间 (decal space)
                    // 注意，viewRayOS 不是一个单位向量，所以不要规一化它，它是一个方向向量，视图空间z的长度是1
                    decalSpaceScenePos = i.cameraPosOSAndFogFactor.xyz + i.viewRayOS.xyz * sceneDepthVS;
                    
#if _SupportOrthographicCamera
                }
#endif

                // unity 的 cube 的顶点坐标范围是 [-0.5, 0.5,]，我们把它转到 [0,1] 的范围，用于映射UV
                // 只有你使用 cube 作为 mesh filter 时才能这么干
                float2 decalSpaceUV = decalSpaceScenePos.xy + 0.5;

                // 剔除逻辑
                //===================================================
                // 剔除在 cube 以外的像素信息
                float shouldClip = 0;
#if _ProjectionAngleDiscardEnable
                // 也丢弃 “场景法向不面对贴花投射器方向” 的像素
                // 使用 ddx 和 ddy 重建场景法线信息
                // ddx 就是右边的像素块的值减去左边像素块的值，而ddy就是下面像素块的值减去上面像素块的值。
                // ddx 和 ddy 的结果就是副切线和切线方向，利用右手定理，叉乘 (cross) 后就是法线，最后执行归一化 (normalize) 得到法线单位向量
                float3 decalSpaceHardNormal = normalize(cross(ddx(decalSpaceScenePos), ddy(decalSpaceScenePos)));

                // 判断是否进行剔除
                // 注：decalSpaceHardNormal.z = dot(decalForwardDir, sceneHardNormalDir)
                shouldClip = decalSpaceHardNormal.z > _ProjectionAngleDiscardThreshold ? 0 : 1;
#endif
                // 执行剔除
                // 如果 ZWrite 关闭，在移动设备上 clip() 函数是足够效率的，因为它不会写入深度缓冲，所以GPU渲染管线不会卡住（经过ARM官方人员确认过）
                clip(0.5 - abs(decalSpaceScenePos) - shouldClip);
                //===================================================

                // 贴花UV计算
                // _MainTex_ST.xy: 表示uv的tilling
                // _MainTex_ST.zw: 表示uv的offset     
                float2 uv = decalSpaceUV.xy * _MainTex_ST.xy + _MainTex_ST.zw;//Texture tiling & offset
#if _FracUVEnable
                // UV裂缝处理
                uv = frac(uv);
#endif
                // 贴花纹理采样
                half4 col = tex2D(_MainTex, uv);
                // 与颜色相乘
                col *= _Color;
                // 透明通道重新映射
                col.a = saturate(col.a * _AlphaRemap.x + _AlphaRemap.y);
                // 插值
                col.rgb *= lerp(1, col.a, _MulAlphaToRGB);

#if _UnityFogEnable
                // 混合像素颜色与雾色。你可以选择使用MixFogColor来覆盖雾色
                col.rgb = MixFog(col.rgb, i.cameraPosOSAndFogFactor.a);
#endif
                return col;
            }
            ENDHLSL
        }
    }
}