using UnityEngine;

using RosMessageTypes.Sensor;
using UnitySensors.Data.Texture;
using UnitySensors.Sensor;
using Unity.Collections;

namespace UnitySensors.ROS.Serializer.Image
{
    [System.Serializable]
    public class ImageRawMsgSerializer<T> : RosMsgSerializer<T, ImageMsg> where T : UnitySensor, ITextureInterface
    {
        [SerializeField]
        private HeaderSerializer _header;

        public override void Init(T sensor)
        {
            base.Init(sensor);
            _header.Init(sensor);

            _msg.width = (uint)sensor.texture.width;
            _msg.height = (uint)sensor.texture.height;
            _msg.encoding = "rgba16";
        }

        public override ImageMsg Serialize()
        {
            _msg.header = _header.Serialize();
            _msg.data = sensor.texture.GetRawTextureData();
            return _msg;
        }
    }
}
