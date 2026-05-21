Shader "ArcanelikeStylized/StylizedCharacterShader"
{
    Properties
    {
        [Header(Debug)] [Space]
        _ShowLightingPass("Show Lighting Pass", int) = 0.0
        _ShowRimLightingPass("Show Rim Lighting Pass", int) = 0.0
        [Header(Base Texture and Color Correction)] [Space]
        _BaseColor("Base Color Tint", Color) = (1, 1, 1, 1)
        _BaseGain("Base Color Gain", Range(-1.0, 1.0)) = 0.0
        _BaseLift("Base Color Lift", Range(0.0, 1.0)) = 0.0
        _BaseTexture("Base Texture", 2D) = "white" {}
        [Header(Shadow Color Correction)] [Space]
        _ShadowColor("Shadow Color", Color) = (0.5, 0.5, 0.5, 1)
        _ShadowGain("Shadow Color Gain", Range(-1.0, 1.0)) = 0.0
        _ShadowLift("Shadow Color Lift", Range(0.0, 1.0)) = 0.0
        _ShadowStepEdge("Shadow Step Edge", Range(0.0, 1.0)) = 0.0
        _ShadowStepSmoothness("Shadow Step Edge Smoothness", Range(0.0, 1.0)) = 0.0
        [Header(Rim Lighting)] [Space]
        _RimLightOffset("Rim Light Offset", Vector) = (0, 2, 2, 0)
        [HDR] _RimLightColor("Rim Light Color", Color) = (1, 1, 0, 1)
        _OverlayRimColor("Overlay Rim Light Color", int) = 1
        _RimLightStepEdge("Rim Light Step Edge", Range(0.0, 1.0)) = 0.0
        _RimLightMaskWithLightingPass("Mask with Lighting Pass", int) = 0.0
        _RimLightLightingPassMaskStepEdge("Lighting Pass Mask Step Edge", Float) = 0.0
        [Header(Normal Mapping)] [Space]
        _NormalTexture("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Float) = 1.0                  
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Tags {
                "LightMode" = "UniversalForward"
            }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

                #pragma vertex vert
                #pragma fragment frag

                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
                #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
                #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

                CBUFFER_START(UnityPerMaterial)
                int _ShowLightingPass;
                int _ShowRimLightingPass;
                float _BaseGain;
                float _BaseLift;
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float4 _ShadowColor;
                float _ShadowGain;
                float _ShadowLift;
                float _ShadowStepEdge;
                float _ShadowStepSmoothness;
                float4 _RimLightOffset;
                float4 _RimLightColor;
                int _OverlayRimColor;
                float _RimLightStepEdge;
                int _RimLightMaskWithLightingPass;
                float _RimLightLightingPassMaskStepEdge;
                float _NormalStrength;                             
                CBUFFER_END

                TEXTURE2D(_BaseTexture);
                SAMPLER(sampler_BaseTexture);

                TEXTURE2D(_NormalTexture);
                SAMPLER(sampler_NormalTexture);

                struct appdata {
                    float4 positionOS : POSITION;
                    float2 uv: TEXCOORD0;
                    float3 normalOS: NORMAL;
                    float4 tangentOS: TANGENT;
                };

                struct v2f{
                    float4 positionCS: SV_POSITION;
                    float2 uv: TEXCOORD0;
                    float3 normalWS: TEXCOORD1;
                    float3 positionWS: TEXCOORD2;
                    float3 viewWS: TEXCOORD3;
                    float4 tangentWS: TEXCOORD4;
                };

                float3 GetRimLightPosition(float3 viewWS, float3 positionWS, float3 offsetWS)
                {
                    float3 forward = normalize(viewWS);

                    //calculate basis vectors
                    float3 tempUp = abs(viewWS.y) < 0.99 
                      ?  float3(0,1,0)
                      :  float3(1,0,0);
                    float3 side = normalize(cross(tempUp, forward));
                    float3 up = cross(side, forward);

                    // tranform offset to viewDirWS orthonormal basis
                    float3 offsetRebased = float3(
                        offsetWS.x * side +
                        offsetWS.y * up +
                        offsetWS.z * viewWS
                        );

                    float3 offsetPosition = positionWS + offsetRebased;
                    return offsetPosition;
                }

                v2f vert(appdata i)
                {
                    v2f o = (v2f)0;
                    o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                    o.uv = TRANSFORM_TEX(i.uv, _BaseTexture);

                    o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                    o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                    o.viewWS = GetWorldSpaceViewDir(o.positionWS);

                    o.tangentWS = float4(TransformObjectToWorldDir(i.tangentOS.xyz), i.tangentOS.w);

                    return o;
                }

                float4 frag(v2f i) : SV_TARGET
                {      
                    float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                    float3 viewWS = normalize(i.viewWS);
                    float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);

                    // ------------------------------------------------------
                    // Normal map offset
                    float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv), _NormalStrength);
                    float3 binormalWS = cross(i.normalWS, i.tangentWS.xyz) * i.tangentWS.w * unity_WorldTransformParams.w;
                    normalWS = normalize(
                        normalTS.x * i.tangentWS.xyz +
                        normalTS.y * binormalWS +
                        normalTS.z * normalWS
                       );
                    // ------------------------------------------------------

                    // Get main light and sample it's shadow map 
                    Light mainLight = GetMainLight(shadowCoord);
                    float mainLightShadows = mainLight.distanceAttenuation * mainLight.shadowAttenuation;

                    // ------------------------------------------------------
                    // Diffuse lighting - Calculate the lighting pass mask
                    float diffuseLighting = saturate(dot(normalWS, mainLight.direction));
                    float lightingPass = mainLightShadows * diffuseLighting;
                    // ------------------------------------------------------

                    // ------------------------------------------------------
                    // Lighting Pass "Shadows mask" smoothstep
                    int dontUseShadowSteppedMask = (int)(saturate(1 - _ShadowStepEdge - _ShadowStepSmoothness));
                    float shadowEdge1 = saturate(_ShadowStepEdge - _ShadowStepSmoothness/2);
                    float shadowEdge2 = saturate(_ShadowStepEdge + _ShadowStepSmoothness/2);
                    float lightingPassMaskStepped = smoothstep(shadowEdge1, shadowEdge2, lightingPass);
                    float lightingPassMask = lerp(lightingPassMaskStepped, lightingPass, dontUseShadowSteppedMask);
                    // ------------------------------------------------------
       
                    // ------------------------------------------------------
                    // Base color and color correction
                    float baseGain = (_BaseGain + 1.0); // convert from (-1,1) to (0,2)
                    float4 baseColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv) * _BaseColor;

                    baseColor = baseColor * (baseGain - _BaseLift) + _BaseLift;

                    float shadowGain = (_ShadowGain + 1.0); // convert from (-1,1) to (0,2)
                    float4 shadowColor = baseColor * _ShadowColor * (shadowGain - _ShadowLift) + _ShadowLift;
                    // ------------------------------------------------------

                    // Final color of the "Lighting pass" stage
                    float4 finalColor = lerp(shadowColor, baseColor, lightingPassMask);

                    // ------------------------------------------------------
                    // Rim Light - position defined by offset relative to view direction
                    float3 rimLightPosition = GetRimLightPosition(viewWS.xyz, i.positionWS.xyz, _RimLightOffset.xyz);
                    float3 toRimLightDirection = normalize(rimLightPosition - i.positionWS) * -1; //has to be flipped, dunno why, goes against my intuition
                    // stepped lighting pass mask
                    int dontUseSteppedLightingMask = (int)(saturate(1 - _RimLightLightingPassMaskStepEdge));
                    float rimLightingPassMaskStepped = step(_RimLightLightingPassMaskStepEdge, lightingPass);
                    float rimLightingPassMask = lerp(rimLightingPassMaskStepped, lightingPassMask, dontUseSteppedLightingMask);
                    //either full white or lighting pass mask (stepped or not) depending on _RimLightMaskWithLightingPass and _RimLightLightingPassMaskStepEdge
                    rimLightingPassMask = saturate(rimLightingPassMask + saturate(1 - _RimLightMaskWithLightingPass));
                    
                    float rimLightingMask = saturate(dot(normalWS, toRimLightDirection)) * rimLightingPassMask;

                    //Rim Light mask step
                    int dontUseSteppedMask = (int)(saturate(1 -_RimLightStepEdge));
                    float rimLightingMaskStepped = step(_RimLightStepEdge, rimLightingMask);
                    rimLightingMask = lerp(rimLightingMaskStepped, rimLightingMask, dontUseSteppedMask);

                    // Overlay between base colour and rim colour
                    float4 result1 = 1.0 - 2.0 * (1.0 - finalColor) * (1.0 - _RimLightColor);
                    float4 result2 = 2.0 * finalColor * _RimLightColor;
                    float4 zeroOrOne = step(finalColor, 0.5);

                    float4 rimColor = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
                    rimColor = lerp(finalColor, rimColor, rimLightingMask);
                    // Switch between Overlayed or Base Rim Color
                    rimColor = lerp(_RimLightColor, rimColor, _OverlayRimColor);
                    // ------------------------------------------------------

                    finalColor = lerp(finalColor, rimColor, rimLightingMask);

                    // debug show pass masks - lighting takes precedence
                    finalColor = lerp(finalColor, lightingPassMask, _ShowLightingPass);
                    finalColor = lerp(finalColor, rimLightingMask, saturate(_ShowRimLightingPass - _ShowLightingPass));

                    return finalColor;                    
                }

            ENDHLSL
        }

        Pass {
            Tags {
                "LightMode" = "ShadowCaster"
             }

             ZWrite On
             ColorMask 0

             HLSLPROGRAM
             #pragma vertex shadowPassVert
             #pragma fragment shadowPassFrag

             #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
             #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
             #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

             #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

             float3 _LightDirection;
             float3 _LightPosition;

             struct appdata{
                 float4 positionOS: POSITION;
                 float3 normalOS: NORMAL;
             };

             struct v2f{
                 float4 positionCS: SV_POSITION;
             };

             float4 GetShadowPositionHClip(appdata input)
             {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif
                
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));             
                //positionCS = ApplyShadowClamping(positionCS);    
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                
                return positionCS;
             }

             v2f shadowPassVert(appdata i){
                 v2f o = (v2f)0;

                 o.positionCS = GetShadowPositionHClip(i);

                 return o;
             }

             float4 shadowPassFrag(v2f i) : SV_TARGET {
                 return 0;
             }

             ENDHLSL
        }

        Pass {
            Tags {
                "LightMode" = "DepthOnly"
            }

            ZWrite On
            ColorMask R

            HLSLPROGRAM

                #pragma vertex depthOnlyVert
                #pragma fragment depthOnlyFrag

                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

                struct appdata{
                    float4 positionOS : POSITION;
                };

                struct v2f{
                    float4 positionCS : SV_POSITION;
                };

                v2f depthOnlyVert(appdata i)
                {
                    v2f o = (v2f)0;
                    o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                    return o;
                }

                float depthOnlyFrag(v2f i): SV_TARGET
                {
                    return i.positionCS.z;
                }

            ENDHLSL
        }

        Pass {
            Tags {
                "LightMode" = "DepthNormals"
            }

            ZWrite On

            HLSLPROGRAM
                #pragma vertex depthNormalsVert
                #pragma fragment depthNormalsFrag

                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

                CBUFFER_START(UnityPerMaterial)
                int _ShowLightingPass;
                int _ShowRimLightingPass;
                float _BaseGain;
                float _BaseLift;
                float4 _BaseColor;
                float4 _BaseTexture_ST;
                float4 _ShadowColor;
                float _ShadowGain;
                float _ShadowLift;
                float _ShadowStepEdge;
                float _ShadowStepSmoothness;
                float4 _RimLightOffset;
                float4 _RimLightColor;
                int _OverlayRimColor;
                float _RimLightStepEdge;
                int _RimLightMaskWithLightingPass;
                float _RimLightLightingPassMaskStepEdge;
                float _NormalStrength;                             
                CBUFFER_END

                TEXTURE2D(_BaseTexture);
                SAMPLER(sampler_BaseTexture);

                TEXTURE2D(_NormalTexture);
                SAMPLER(sampler_NormalTexture);

                struct appdata{
                    float4 positionOS : POSITION;
                    float2 uv: TEXCOORD0;
                    float3 normalOS: NORMAL;
                    float4 tangentOS: TANGENT;
                };

                struct v2f{
                    float4 positionCS : SV_POSITION;
                    float2 uv: TEXCOORD0;
                    float3 normalWS: TEXCOORD1;                    
                    float4 tangentWS: TEXCOORD2;
                };

                v2f depthNormalsVert(appdata i)
                {
                    v2f o = (v2f)0;
                    o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                    o.normalWS = TransformObjectToWorldNormal(i.normalOS);
                    o.normalWS = NormalizeNormalPerVertex(o.normalWS);

                    o.uv = TRANSFORM_TEX(i.uv, _BaseTexture);
                    o.tangentWS = float4(TransformObjectToWorldDir(i.tangentOS.xyz), i.tangentOS.w);
                    return o;
                }

                float4 depthNormalsFrag(v2f i): SV_TARGET
                { 
                    float3 normalWS = NormalizeNormalPerPixel(i.normalWS);

                    float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalTexture, sampler_NormalTexture, i.uv), _NormalStrength);
                    float3 binormalWS = cross(i.normalWS, i.tangentWS.xyz) * i.tangentWS.w * unity_WorldTransformParams.w;
                    normalWS = normalize(
                        normalTS.x * i.tangentWS.xyz +
                        normalTS.y * binormalWS +
                        normalTS.z * normalWS
                       );

                    return float4(normalWS, 0.0f);
                }

            ENDHLSL
        }
    }
}