Shader "Custom/ScreenSpaceShader"
{
    Properties
    {
        _MainTex("Base (RGB)", 2D) = "white" {}
        _RadiationPatternMask("RadiationPatternMask", 2D) = "white" {}
        _RoughnessMap("RoughnessMap", 2D) = "white" {}
        _Blend("Blend", Range(0, 1)) = 0
        _MaxDistance("MaxDistance", Range(0, 1)) = 0
        _MaxVelocity("_MaxVelocity", Range(0, 100)) = 1
        _LerpSpecular("LerpSpecular", Range(0, 1)) = 0
        _LerpNormal("LerpNormal", Range(0, 1)) = 0
        _ViewDir("_ViewDir", Vector) = (0,0,0,0)
        _LowerChirpFrequency("_LowerChirpFrequency", float) = 1
        _ChirpRate("_ChirpRate", float) = 1
        _fov("_fov", float) = 100
        _BandwidthOfTheChirp("_BandwidthOfTheChirp", float) = 1
    }
    SubShader
        {
            Tags { "RenderType" = "Opaque" }

            Pass
            {
                CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                #pragma target 5.0
                #include "UnityCG.cginc"

                struct v2f
                {
                    float4 pos : SV_POSITION;
                    float4 screenuv : TEXCOORD1;
                };

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.screenuv = ComputeScreenPos(o.pos);
                return o;
            }

            sampler2D _CameraDepthTexture;
            sampler2D _BTex;
            uniform sampler2D _MainTex;
            uniform sampler2D _RadiationPatternMask;
            uniform sampler2D _RoughnessMap;
            uniform float _Blend;
            uniform float _MaxDistance;
            uniform float _MaxVelocity;
            uniform half _LerpSpecular;
            uniform half _LerpNormal;

            sampler2D _CameraGBufferTexture1;
            sampler2D _CameraGBufferTexture2;

            float4 _ViewDir;
            int _width;
            int _height;
            int _chirpsNumber;
            int _samplesNumber;
            float _ChirpRate;
            int _nrAntennas;
            float _fov;
            float _centerFrequency;
            float _LowerChirpFrequency;
            float _BandwidthOfTheChirp;

            RWStructuredBuffer<float2> _gpuBuffer1 : register(u1);
            RWStructuredBuffer<float2> _gpuBuffer2 : register(u2);

            fixed4 frag(v2f i) : SV_Target
            {
                float4 c = tex2D(_MainTex, i.screenuv);
                float radiationpatternweighting = tex2D(_RadiationPatternMask, i.screenuv).r;
                float roughness = tex2D(_RoughnessMap, i.screenuv).r;

                float2 uv = i.screenuv.xy / i.screenuv.w;
                float depth = Linear01Depth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                float depthprev = Linear01Depth(SAMPLE_DEPTH_TEXTURE(_BTex, uv));

                float4 gbuffer2 = tex2D(_CameraGBufferTexture2, i.screenuv);

                float3 normalvector = float3((gbuffer2.r * 2) - 1, (gbuffer2.g * 2) - 1, (gbuffer2.b * 2) - 1);

                float4 gbuffer1 = tex2D(_CameraGBufferTexture1, i.screenuv);

                float pi = 3.14159;
                float spacing;

                int x = int(i.screenuv.x * _width);
                int y = int(i.screenuv.y * _height);

                float azimuth_angle;
                float elevation_angle;
                float f;
                float phase_shift_rx2;
                float phase_shift_rx3;
                float phase_shift_rx4;
                float c0 = 299792458.0f;
                float lambda;

                _centerFrequency = _LowerChirpFrequency + (_BandwidthOfTheChirp * 0.5f);
                lambda = c0 / _centerFrequency;
                spacing = lambda / 2.0f;

                f = (_width * 0.5f) / tan((_fov * pi / 180.0f) * 0.5f);

                if (depth < 1)
                {
                    azimuth_angle = atan((x - 0.5f * _width) / f);
                    elevation_angle = atan((y - 0.5f * _height) / f);
                    phase_shift_rx2 = (2 * pi * spacing * sin(azimuth_angle)) / lambda;
                    phase_shift_rx3 = (4 * pi * spacing * sin(azimuth_angle)) / lambda;
                    phase_shift_rx4 = (6 * pi * spacing * sin(azimuth_angle)) / lambda;
                }
                else
                {
                    phase_shift_rx2 = 0.0f;
                    phase_shift_rx3 = 0.0f;
                    phase_shift_rx4 = 0.0f;
                }

                float distance = depth * _MaxDistance;

                if (distance >= _MaxDistance)
                {
                    distance = 0.0f;
                }

                float delta_t = unity_DeltaTime.x;
                float velocity = (((depth - depthprev) * _MaxDistance)) / delta_t;

                float diffuse;
                float specular;
                float3 sensor_direction = _ViewDir;

                specular = max(0.0, dot(reflect(-sensor_direction, normalvector), sensor_direction));
                diffuse = dot(sensor_direction, normalvector);

                float Rij = gbuffer1.a * diffuse;
                float distancefin = distance;

                float fs = 2000000.0f;

                for (uint chirps = 0; chirps < _chirpsNumber; chirps++)
                {
                    for (uint i = 0; i < _samplesNumber; i++)
                    {
                        float t = (float)(i + 1) / fs; // time vector

                        float tau = (2 / c0) * (distancefin + (velocity * (_samplesNumber / fs) * chirps));

                        float f1 = 2 * pi * _LowerChirpFrequency * tau;
                        float f2 = 2 * pi * _ChirpRate * tau * t;
                        float f3 = -pi * _ChirpRate * tau * tau;

                        float fn = f1 + f2 + f3;

                        float solidrx1 = 0.0f;
                        float solidrx2 = 0.0f;
                        float solidrx3 = 0.0f;
                        float solidrx4 = 0.0f;

                        if (distancefin != 0)
                        {
                            if (_nrAntennas == 1)
                            {
                                solidrx1 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn);
                            }
                            else if (_nrAntennas == 2)
                            {
                                solidrx1 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn);
                                solidrx2 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn + phase_shift_rx2);
                            }
                            else if (_nrAntennas == 3)
                            {
                                solidrx1 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn);
                                solidrx2 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn + phase_shift_rx2);
                                solidrx3 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn + phase_shift_rx3);
                            }
                            else
                            {
                                solidrx1 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn);
                                solidrx2 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn + phase_shift_rx2);
                                solidrx3 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn + phase_shift_rx3);
                                solidrx4 = radiationpatternweighting * (1 / distancefin) * Rij * cos(fn + phase_shift_rx4);
                            }
                        }

                        if (_nrAntennas == 1)
                        {
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = solidrx1;
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = 0.0f;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = 0.0f;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = 0.0f;
                        }
                        else if (_nrAntennas == 2)
                        {
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = solidrx1;
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = solidrx2;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = 0.0f;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = 0.0f;
                        }
                        else if (_nrAntennas == 3)
                        {
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = solidrx1;
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = solidrx2;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = solidrx3;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = 0.0f;
                        }
                        else
                        {
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = solidrx1;
                            _gpuBuffer1[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = solidrx2;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].x = solidrx3;
                            _gpuBuffer2[(chirps * _width * _height * _samplesNumber) + (i * _width * _height) + (y * _width) + x].y = solidrx4;
                        }
                    }

                    distancefin = distance + (velocity * chirps * (_samplesNumber / fs));
                }

                float4 imageeffect;
                imageeffect = lerp(float4(depth, depth, depth, 1), gbuffer1, _LerpSpecular);
                imageeffect = lerp(imageeffect, gbuffer2, _LerpNormal); // lerp with normal texture	
                return lerp(c, imageeffect, 1.0f); // blend cameraview and effects
            }
            ENDCG
        }
    }
}
