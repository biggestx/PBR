Shader "PBR/Smith"
{
	Properties
	{
		_MainTex("Main Texture", 2D) = "white"{}
		_Color("Color", Color) = (1,1,1,1)
		_NormalTex("Normal Textire", 2D) = "bump"{}
		_Specular("Specular", Color) = (1, 1, 1, 1)
		_Roughness("Roughness", Range(0,1)) = 0.5
		_Metalness("Metalness", Range(0,1)) = 0.5
		[Toggle(_DISNEY)] _DISNEY("Disney", float) = 1
	}
	SubShader
	{
		Tags
		{
			"RenderPipeline" = "UniversalPipeline"
			"RenderType" = "Opaque"
			"Queue" = "Geometry+0"
		}
		LOD 100

		Pass
		{
			HLSLPROGRAM

			#pragma prefer_hlslcc gles
			#pragma exclude_renderers d3d11_9x

			#pragma vertex vert
			#pragma fragment frag

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			#pragma multi_compile_instancing
			#pragma multi_compile_fog

			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _SHADOWS_SOFT

			#pragma shader_feature_local _DISNEY

			#define PI 3.14159265359
			#define EPS 0.00001

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;

				float3 worldPos : TEXCOORD1;
				float3 viewDir : TEXCOORD2;

				float3 T : TEXCOORD3;
				float3 B : TEXCOORD4;
				float3 N : TEXCOORD5;

				float4 shadowCoord : TEXCOORD6;
				float fogCoord : TEXCOORD7;

			};

			CBUFFER_START(UnityPerMaterial)

			TEXTURE2D(_MainTex);
			SAMPLER(sampler_MainTex);
			half4 _MainTex_ST;

			TEXTURE2D(_NormalTex);
			SAMPLER(sampler_NormalTex);

			float4 _Color;

			float4 _Specular;
			float _Gloss;
			float _Roughness;
			float _Metalness;


			CBUFFER_END

			void LocalToTBN(half3 normal, float4 tangent, inout float3 T, inout float3 B, inout float3 N)
			{
				half ts = tangent.w * unity_WorldTransformParams.w;

				N = normalize(TransformObjectToWorldNormal(normal));
				T = normalize(TransformObjectToWorldDir(tangent.xyz));
				B = normalize(cross(N, T) * ts);
			}

			inline float3 diffuseLambert(float3 albedo)
			{
				return albedo / PI;
			}

			inline float3 diffuseDisney(float3 base, float roughness, float hl, float nl, float nv)
			{
				float fd90 = 0.5 + 2 * pow(hl, 2) * roughness;
				return  base / PI * (1 + (fd90 - 1) * pow(1 - nl, 5)) * (1 + (fd90 - 1) * pow(1 - nv, 5));
			}

			inline float3 specularBlinnPhong(float roughness, float nh) 
			{
				float alpha_2 = pow(roughness, 4);
				float a = 2 / alpha_2 - 2;
				return 1 / (PI * alpha_2) * pow(nh, a);
			}

			inline float D_GGX_mine(float a2, float nh) // already defined 
			{
				float d = (nh * a2 - nh) * nh + 1;
				return a2 / (PI * d * d);
			}

			float F_Schilick(float3 specColor, float vh)
			{
				float fc = pow(1 - vh, 5);
				return saturate(50.0 * specColor.g) * fc + (1 - fc) * specColor;
			}

			float fPow5(float v)
			{
				return pow(1 - v, 5);
			}
			float3 F_Fresnel(float3 F0, float NdotV, float roughness)
			{
				return F0 + (max(1.0 - roughness, F0) - F0) * fPow5(NdotV);
			}

			float SmithVisibility(float nl, float nv, float k)
			{
				float gl = nl * (1 - k) + k;
				float gv = nv * (1 - k) + k;
				return 1.0 / (gl * gv + 1e-5f);
			}

			float G_SmithBeckmannVisibilityTerm(float nl, float nv, float roughness)
			{
				float c = 0.797884560802865f;
				float k = roughness * c;
				return SmithVisibility(nl, nv, k) * 0.25;
			}

			float G_SchlickGGX(float nv, float roughness)
			{
				float r = roughness + 1.0f;
				float k = (r * r) / 8.0;
				float num = nv;
				float denom = nv * (1.0 - k) + k;

				return num / denom;
			}

			float3 specularBRDF(float nl, float lh, float nh, float nv, float vh, float3 F0, float roughness, float3 specColor)
			{

				float3 F;
				float D;
				float G;

				float a2 = roughness * roughness;

				F = F_Fresnel(F0, nv, roughness);
				D = D_GGX_mine(a2, nh);
				G = G_SmithBeckmannVisibilityTerm(nl, nv, roughness);

				// cook-torrance
				//return saturate((D * F * G) / ((PI * nl) * nv));

				return nl * D * F * G;
				//return (D * F * G) / (nl * nv + EPS);
			}
			float3 sRGB2Lin(float3 col)
			{
				return pow(col, 2.2);
			}
			
			float3 gammaCorrection(float3 v)
			{
				return pow(v, 1.0 / 2.2);
			}

			v2f vert(appdata v)
			{
				v2f o;
				UNITY_SETUP_INSTANCE_ID(v);
				UNITY_TRANSFER_INSTANCE_ID(v, o);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

				o.vertex = TransformObjectToHClip(v.vertex.xyz);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.worldPos = mul(UNITY_MATRIX_M, v.vertex);
				o.viewDir = normalize(_WorldSpaceCameraPos.xyz - mul(GetObjectToWorldMatrix(), float4(v.vertex.xyz, 1.0)).xyz);
				
				LocalToTBN(v.normal, v.tangent, o.T, o.B, o.N);

				VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
				o.shadowCoord = GetShadowCoord(vertexInput);
				o.fogCoord = ComputeFogFactor(o.vertex.z);
				return o;
			}

			half4 frag(v2f i) : SV_Target
			{
				UNITY_SETUP_INSTANCE_ID(i);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

				Light light = GetMainLight(i.shadowCoord);

				float3 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) + _Color;

				float2 uv = i.uv;

				float3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, i.uv));
				float3x3 TBN = float3x3(normalize(i.T), normalize(i.B), normalize(i.N));
				TBN = transpose(TBN);
				normal = normalize(mul(TBN, normal));
				
				float3 lightDir = normalize(light.direction);
				float3 viewDir = normalize(i.viewDir);
				float3 reflectDir = reflect(-viewDir, normal);
				float3 halfDir = normalize(lightDir + viewDir);

				float nv = saturate(dot(normal, viewDir));
				float nl = saturate(dot(normal, lightDir));
				float nh = saturate(dot(normal, halfDir));
				float lv = saturate(dot(lightDir, viewDir));
				float lh = saturate(dot(lightDir, halfDir));
				float vh = saturate(dot(viewDir, halfDir));

				float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, _Metalness);

				float3 diffuse = float3(0, 0, 0);
				#ifdef _DISNEY
				diffuse = diffuseDisney(albedo.rgb, _Roughness, lh, nl, nv) * PI * light.color * nl;
				#else
				diffuse = diffuseLambert(albedo.rgb) * PI * light.color * nl;
				#endif
				
				float3 specular = specularBRDF(nl, lh, nh, nv, vh, F0, _Roughness, _Specular);
				
				half3 ambient = SampleSH(normal);

				float3 color = gammaCorrection(specular + specular) + ambient;

				return half4(color.r, color.g, color.b, 1);
			}



			ENDHLSL

		}
	}
}