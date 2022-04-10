#version 450 core

out vec4 fragColor;

in VS_OUT
{
   vec3 worldPos;
   vec3 normal;
   vec2 texCoords;
} fs_in;

// layout (binding = 0) uniform sampler2D albedoMap;
// layout (binding = 1) uniform sampler2D normalMap;
// layout (binding = 2) uniform sampler2D metallicMap;
// layout (binding = 3) uniform sampler2D roughnessMap;
// layout (binding = 4) uniform sampler2D aoMap;

uniform sampler2D albedoMap;
uniform sampler2D normalMap;
uniform sampler2D metallicMap;
uniform sampler2D roughnessMap;
uniform sampler2D aoMap;

//lights
uniform vec3 lightPositions[4];
uniform vec3 lightColors[4];

uniform vec3 camPos;

const float PI = 3.14159265359;

//http://www.aclockworkberry.com/shader-derivative-functions/
vec3 getNormalFromMap() 
{
   vec3 tangentNormal = texture(normalMap, fs_in.texCoords).xyz * 2.0 - 1.0;

   vec3 Q1 = dFdx(fs_in.worldPos);
   vec3 Q2 = dFdy(fs_in.worldPos);
   vec2 st1 = dFdx(fs_in.texCoords);
   vec2 st2 = dFdy(fs_in.texCoords);

   vec3 N = normalize(fs_in.normal);
   vec3 T = normalize(Q1 * st2.t - Q2 * st1.t);
   vec3 B = -normalize(cross(N, T));
   mat3 TBN = mat3(T, B, N);

   return normalize(TBN * tangentNormal);
}

//the ratio between specular and diffuse reflection
//surface reflects light vs refract light
//F0: surface reflection at zero incidence(N*V)
//在pbr工作流中，简化假设大多数的dielectric surface的F0为常量0.04， metallic surface的F0为其albedo
vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
   return F0 + (1 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

//GGX/Trowbridge-Reitz --disney and Epic Games
float distributionGGX(vec3 N, vec3 H, float roughness)
{
   float a = roughness * roughness;
   float a2 = a * a;
   float NdotH = max(dot(N, H), 0);
   float NdotH2 = NdotH * NdotH;

   float num = a2;
   float denom = (NdotH2 * (a2 - 1.0) + 1.0);
   denom = PI * denom * denom;

   return num / denom;
}

//--disney and Epic Games
float geometrySchlickGGX(float NdotX, float roughness)
{
   float a = (roughness + 1.0) / 2.0;
   float k = a * a / 2.0;

   float num = NdotX;
   float denom = NdotX * (1.0 - k) + k;

   return num / denom;
}

float geometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
   float NdotV = max(dot(N, V), 0);
   float NdotL = max(dot(N, L), 0);
   float gl = geometrySchlickGGX(NdotL, roughness);
   float gv = geometrySchlickGGX(NdotV, roughness);
   return gl * gv;
}

void main()
{
   vec3 albedo = pow(texture(albedoMap, fs_in.texCoords).rgb, vec3(2.2));
   float metallic = texture(metallicMap, fs_in.texCoords).r;
   float roughness = texture(roughnessMap, fs_in.texCoords).r;
   float ao = texture(aoMap, fs_in.texCoords).r;

   vec3 N = normalize(fs_in.normal);
   vec3 V = normalize(camPos - fs_in.worldPos);

   vec3 F0 = vec3(0.04);
   F0 = mix(F0, albedo, metallic);

   vec3 Lo = vec3(0.0);
   //point light source
   for (int i = 0; i < 4; i++)
   {
      vec3 L = normalize(lightPositions[i] - fs_in.worldPos);
      vec3 H = normalize(L + V);

      float distance = length(lightPositions[i] - fs_in.worldPos);
      float attenuation = 1.0 / (distance * distance);
      // calculate per-light radiance
      vec3 radiance = lightColors[i] * attenuation;

      //Cook-Torrance BRDF
      float NDF = distributionGGX(N, H, roughness);
      vec3 F = fresnelSchlick(max(dot(H, V), 0), F0);
      float G = geometrySmith(N, V, L, roughness);

      vec3 numerator = NDF * G * F;
      float denominator = 4.0 * max(dot(N, V), 0) * max(dot(N, L), 0);
      vec3 specular = numerator / (denominator + 0.0001);  //add 0.0001 to prevent a divide by zero

      vec3 kS = F;
      vec3 kD = vec3(1.0) - kS;
      // kS表达获取反射的光能量比率，剩下的光能量比率便是表达折射即kD
      // 进一步的，metallic surface并不会折射光，则没有漫反射
      kD *= 1.0 - metallic;

      // add to outgoing radiance Lo
      float NdotL = max(dot(N, L), 0);
      Lo += (kD * albedo / PI + specular) * radiance * NdotL;
   }

   vec3 ambient = vec3(0.03) * albedo * ao;
   vec3 color = ambient + Lo;

   //到目前为止都在假设所有计算都在linear color space中进行
   //在linear space 中计算光照非常重要，因PBR需要所有的输入都是线性的。
   // 因光输入接近它们的物理等效值，以便它们的radiance或者color values可以在高光谱(spectrum)范围内变化很大
   //因此由于默认的low dynamic range(LDR)输出， Lo可以迅速增长到非常高的水平，然后钳制在0.0~1.0之间
   //着色过程的最后需要两步走： tone/exposure map the high dynamic range(HDR)以及gamma cirrection
   //如 Reinhard tone map
   color = color / (color + vec3(1.0));
   color = pow(color, vec3(1.0 / 2.2));

   fragColor = vec4(color, 1.0);
}



