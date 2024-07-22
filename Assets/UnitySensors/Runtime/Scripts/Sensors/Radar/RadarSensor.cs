using System.Collections;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Rendering;

namespace UnitySensors.Sensor.Radar
{
    [RequireComponent(typeof(UnityEngine.Camera))]
    public class RadarSensor : UnitySensor
    {
        [SerializeField]
        [Range(0.0f, 179.0f)]
        private float _fov = 100.0f;

        [SerializeField]
        [Range(1, 32)]
        private int _chirps = 16;

        [SerializeField]
        [Range(1, 1024)]
        private int _samples = 256;

        [SerializeField]
        [Range(1, 2)]
        private int _recvConfig = 1;

        [SerializeField]
        [Range(1, 4)]
        private int _antennas = 1;

        [SerializeField]
        [Range(10000.0f, 10000000.0f)]
        private float _samplingFrequency = 2000000.0f;

        [SerializeField]
        private float _lowerFrequency;

        [SerializeField]
        private float _bandWidth;

        [SerializeField]
        private Texture _RadiationPatternMask;


        private ComputeBuffer gpuBuffer1;
        private ComputeBuffer gpuBuffer2;

        private float Ts;
        private float lambda;
        private float centerFrequency;
        private float K;
        private float maxRange;
        private float maxVelocity;
        private float c0 = 299792458.0f;
        private RenderTexture pastFrame;
        private RenderTexture holdcurrentFrame;

        private Thread thread;

        private UnityEngine.Vector2[] vec1;
        private UnityEngine.Vector2[] vec2;
        private UnityEngine.Vector2[] data1;
        private UnityEngine.Vector2[] data2;

        private int width;
        private int height;
        private float[] t;

        private bool help;

        private UnityEngine.Camera _m_camera;
        public UnityEngine.Camera m_camera { get => _m_camera; }

        Material _mat;
        Material _copyDepthMat;

        private int saveChirps;
        private int saveSamples;

        protected override void Init()
        {
            _mat = new Material(Shader.Find("Custom/ScreenSpaceShader"));
            _copyDepthMat = new Material(Shader.Find("Custom/CopyDepthShader"));

            saveChirps = _chirps;
            saveSamples = _samples;

            _m_camera = GetComponent<UnityEngine.Camera>();

            _m_camera.renderingPath = RenderingPath.DeferredShading;
            _m_camera.depthTextureMode = DepthTextureMode.Depth;

            pastFrame = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.ARGBFloat);
            holdcurrentFrame = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.ARGBFloat);

            Ts = saveSamples / _samplingFrequency;
            K = _bandWidth / Ts;
            centerFrequency = _lowerFrequency + (_bandWidth * 0.5f);
            lambda = c0 / centerFrequency;
            maxRange = c0 * saveSamples / (4.0f * _bandWidth);
            maxVelocity = lambda / (4.0f * Ts);

            help = true;
        }

        private void OnRenderImage(RenderTexture source, RenderTexture destination)
        {
            if(_antennas <= 2)
            {
                if(gpuBuffer1 == null)
                {
                    int number;
                    number = _m_camera.pixelWidth * _m_camera.pixelHeight * saveSamples * saveChirps;
                    Graphics.ClearRandomWriteTargets();
                    gpuBuffer1 = new ComputeBuffer(number, 2 * sizeof(float), ComputeBufferType.Default);
                    Graphics.SetRandomWriteTarget(1, gpuBuffer1);
                }
            }
            else
            {
                if(gpuBuffer1 == null && gpuBuffer2 == null)
                {
                    int number;
                    number = _m_camera.pixelWidth * _m_camera.pixelHeight * saveSamples * saveChirps;
                    Graphics.ClearRandomWriteTargets();
                    gpuBuffer1 = new ComputeBuffer(number, 2 * sizeof(float), ComputeBufferType.Default);
                    gpuBuffer2 = new ComputeBuffer(number, 2 * sizeof(float), ComputeBufferType.Default);
                    Graphics.SetRandomWriteTarget(1, gpuBuffer1);
                    Graphics.SetRandomWriteTarget(2, gpuBuffer2);
                }
            }

            if(Screen.width != pastFrame.width || Screen.height != pastFrame.height)
            {
                pastFrame = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.ARGBFloat);
                holdcurrentFrame = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.ARGBFloat);
            }

            if (_antennas <= 2)
            {
                Graphics.SetRandomWriteTarget(1, gpuBuffer1);
                _mat.SetBuffer("_gpuBuffer1", gpuBuffer1);
            }
            else
            {
                Graphics.SetRandomWriteTarget(1, gpuBuffer1);
                Graphics.SetRandomWriteTarget(2, gpuBuffer2);
                _mat.SetBuffer("_gpuBuffer1", gpuBuffer1);
                _mat.SetBuffer("_gpuBuffer2", gpuBuffer2);
            }

            _mat.SetInt("_width", _m_camera.pixelWidth);
            _mat.SetInt("_height", _m_camera.pixelHeight);
            _mat.SetInt("_chirpsNumber", saveChirps);
            _mat.SetInt("_samplesNumber", saveSamples);
            _mat.SetFloat("_fov", _fov);
            _mat.SetInt("_NrAntennas", _antennas);
            _mat.SetInt("_ReceiverConfig", _recvConfig);
            _mat.SetFloat("_ChirpRate", K);
            _mat.SetFloat("_LowerChirpFrequency", _lowerFrequency);
            _mat.SetFloat("_BandwidthOfTheChirp", _bandWidth);
            _mat.SetTexture("_BTex", pastFrame);
            _mat.SetFloat("_MaxDistance", maxRange);
            _mat.SetFloat("_MaxVelocity", maxVelocity);

            Graphics.Blit(source, holdcurrentFrame, _copyDepthMat);
            Shader.SetGlobalTexture("_HoldDepthTexture", holdcurrentFrame);
            Graphics.Blit(source, destination, _mat);
            Graphics.Blit(source, pastFrame, _copyDepthMat);

            Graphics.ClearRandomWriteTargets();
        }

        protected override void UpdateSensor()
        {
            //_m_camera.farClipPlane = maxRange;

            if (_RadiationPatternMask != null)
            {
                _mat.SetTexture("_RadiationPatternMask", _RadiationPatternMask);
            }
            else
            {
                _mat.SetTexture("_RadiationPatternMask", Texture2D.whiteTexture);
            }

            _mat.SetVector("_ViewDir", new UnityEngine.Vector4(_m_camera.transform.forward.x,
                _m_camera.transform.forward.y, 
                _m_camera.transform.forward.z, 0));

            _m_camera.fieldOfView = _fov;

            if (!LoadRawData()) return;

            if (onSensorUpdated != null)
                onSensorUpdated.Invoke();
        }

        protected bool LoadRawData()
        {
            bool result = false;
            width = Screen.width;
            height = Screen.height;

            //vec1 = new UnityEngine.Vector2[_m_camera.pixelWidth * _m_camera.pixelHeight * saveSamples * saveChirps];

            //data1 = new UnityEngine.Vector2[saveSamples * saveChirps];
            //data2 = new UnityEngine.Vector2[saveSamples * saveChirps];

            AsyncGPUReadback.Request(gpuBuffer1, request =>
            {
                if (request.hasError) { }
                else
                {
                    var data = request.GetData<Vector2>();
                    Debug.Log(data[5000]);
                    result = true;
                }
            });
            AsyncGPUReadback.WaitAllRequests();
            return result;
        }



        protected override void OnSensorDestroy()
        {
            if (gpuBuffer1 != null)
            {
                gpuBuffer1.Dispose();
            }
            if (gpuBuffer2 != null)
            {
                gpuBuffer2.Dispose();
            }

            gpuBuffer1 = null;
            gpuBuffer2 = null;
        }
    }
}
