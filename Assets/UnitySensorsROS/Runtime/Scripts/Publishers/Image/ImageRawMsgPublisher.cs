using UnityEngine;
using RosMessageTypes.Sensor;
using UnitySensors.Data.Texture;
using UnitySensors.Sensor;
using UnitySensors.ROS.Serializer.Image;
using UnitySensors.ROS.Publisher;

namespace UnitySensors.ROS.Publisher.Image
{

}
public class ImageRawMsgPublisher<T> : RosMsgPublisher<T, ImageRawMsgSerializer<T>, ImageMsg> where T : UnitySensor, ITextureInterface
{
}
