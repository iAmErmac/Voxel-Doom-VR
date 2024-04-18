//===========================================================================
//
// CHEELLO VOXEL DOOM MASTER SHADER
//
// License: GPL v3.0
//
//===========================================================================

mat3 GetTBN(void);
vec3 GetNormMap(mat3 tbn, vec2 texcoord);
vec3 GetSpecMap(vec2 texcoord);
vec2 ParallaxMap(mat3 tbn);
vec3 GetBumpedNormal(mat3 tbn, vec2 texcoord);

//===========================================================================
//
//
//
//===========================================================================

Material ProcessMaterial()
{
    mat3 tbn = GetTBN();
    vec2 texCoord = ParallaxMap(tbn);

    Material material;
    material.Base = getTexel(texCoord);
    material.Normal = GetBumpedNormal(tbn, texCoord);
#if defined(SPECULAR)
    material.Specular = texture(speculartexture, texCoord).rgb;
    material.Glossiness = uSpecularMaterial.x;
    material.SpecularLevel = uSpecularMaterial.y;
#endif
#if defined(PBR)
    material.Metallic = texture(metallictexture, texCoord).r;
    material.Roughness = texture(roughnesstexture, texCoord).r;
    material.AO = texture(aotexture, texCoord).r;
#endif
#if defined(BRIGHTMAP)
    material.Bright = texture(brighttexture, texCoord);
#endif
    return material;
}

//===========================================================================
//
//
//
//===========================================================================

vec3 GetBumpedNormal(mat3 tbn, vec2 texcoord)
{
#if defined(NORMALMAP)
    vec3 map = texture(normaltexture, texcoord).xyz;
    map = map * 255./127. - 128./127.; // Math so "odd" because 0.5 cannot be precisely described in an unsigned format
    map.xy *= vec2(0.5, -0.5); // Make normal map less strong and flip Y
    return normalize(tbn * map);
#else
    return normalize(vWorldNormal.xyz);
#endif
}

//===========================================================================
//
//
//
//===========================================================================

void SetupMaterial(inout Material mat)
{
	vec2 texCoord = vec2(.0);

	// don't use the shader in 2D mode
	// yes, branching bad hurrdurr. but there's no other way in GZDoom, unfortunately.
	// WARNING: this will produce a compile error in VKDoom because we got rid of uniforms
	// in VKD. I won't bother dealing with this until VKDoom has been officially released - Nash
	if (uFogEnabled == -3)
	{
		texCoord = vTexCoord.st;
		mat.Normal = ApplyNormalMap(texCoord);
	}
	else
	{
		mat3 tbn = GetTBN();
		texCoord = ParallaxMap(tbn);
		mat.Normal = GetNormMap(tbn, texCoord);
	}

	mat.Base = getTexel(texCoord);

#if defined(SPECULAR)
	mat.Specular = GetSpecMap(texCoord);
	mat.Glossiness = uSpecularMaterial.x;
	mat.SpecularLevel = uSpecularMaterial.y;
#endif
#if defined(PBR)
	mat.Metallic = texture(metallictexture, texCoord).r;
	mat.Roughness = texture(roughnesstexture, texCoord).r;
	mat.AO = texture(aotexture, texCoord).r;
#endif
	mat.Bright = texture(brighttexture, texCoord);
}

//===========================================================================
//
//
//
//===========================================================================

vec3 GetNormMap(mat3 tbn, vec2 texcoord)
{
#if defined(NORMALMAP)
	vec3 map = texture(normaltexture, texcoord).xyz;
	// Math so "odd" because 0.5 cannot be precisely described in an unsigned format
	map = map * 255.0 / 127.0 - 128.0 / 127.0;
	// Make normal map less strong and flip Y
	map.xy *= vec2(0.5, -0.5);
	return normalize(tbn * map);
#else
	return normalize(vWorldNormal.xyz);
#endif
}

//===========================================================================
//
//
//
//===========================================================================

#if defined(SPECULAR)
vec3 GetSpecMap(vec2 texcoord)
{
	return texture(speculartexture, texCoord).rgb;
}
#endif

//===========================================================================
//
//
//
//===========================================================================

// Tangent/bitangent/normal space to world space transform matrix
mat3 GetTBN(void)
{
	vec3 n = normalize(vWorldNormal.xyz);
	vec3 p = pixelpos.xyz;
	vec2 uv = vTexCoord.st;

	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(n, dp2); // cross(dp2, n);
	vec3 dp1perp = cross(dp1, n); // cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame
	float invmax = inversesqrt(max(dot(t, t), dot(b, b)));
	return mat3(t * invmax, b * invmax, n);
}

//===========================================================================
//
//
//
//===========================================================================

#if defined(heightTex)
float GetHeightTexAt(vec2 currentTexCoords)
{
    return 0.5 - texture(heightTex, currentTexCoords).r;
}
#endif

vec2 ParallaxMap(mat3 tbn)
{
	vec2 T = vTexCoord.st;

	// material is too far away
	if (pixelpos.w > 1024.0)
		return T;

#if defined(heightTex)
	const float parallaxScale = 0.4;
	const float minLayers = 12.0;
	const float maxLayers = 16.0;

	// Calculate fragment view direction in tangent space
	mat3 invTBN = transpose(tbn);
	vec3 V = normalize(invTBN * (uCameraPos.xyz - pixelpos.xyz));

	// clamp is required due to precision loss
	float numLayers = mix(maxLayers, minLayers, clamp(abs(V.z), 0.0, 1.0));

	// calculate the size of each layer
	float layerDepth = 1.0 / numLayers;

	// depth of current layer
	float currentLayerDepth = 0.0;

	// the amount to shift the texture coordinates per layer (from vector P)
	vec2 P = V.xy * parallaxScale;
	vec2 deltaTexCoords = P / numLayers;
	vec2 currentTexCoords = T + (P * 0.07);
	float currentDepthMapValue = GetHeightTexAt(currentTexCoords);

	while (currentLayerDepth < currentDepthMapValue)
	{
		// shift texture coordinates along direction of P
		currentTexCoords -= deltaTexCoords;

		// get depthmap value at current texture coordinates
		currentDepthMapValue = GetHeightTexAt(currentTexCoords);

		// get depth of next layer
		currentLayerDepth += layerDepth;
	}

	deltaTexCoords *= 0.5;
	layerDepth *= 0.5;

	currentTexCoords += deltaTexCoords;
	currentLayerDepth -= layerDepth;

	const int _reliefSteps = 14;
	int currentStep = _reliefSteps;
	while (currentStep > 0)
	{
		float currentGetHeightTexAt = GetHeightTexAt(currentTexCoords);
		deltaTexCoords *= 0.5;
		layerDepth *= 0.5;


		if (currentGetHeightTexAt > currentLayerDepth)
		{
			currentTexCoords -= deltaTexCoords;
			currentLayerDepth += layerDepth;
		}

		else
		{
			currentTexCoords += deltaTexCoords;
			currentLayerDepth -= layerDepth;
		}
		currentStep--;
	}

	return currentTexCoords - (P * 0.01);
#else
	return T;
#endif
}