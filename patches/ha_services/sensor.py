import typing

from ha_services.exceptions import InvalidStateValue
from ha_services.mqtt4homeassistant.components import BaseComponent
from ha_services.mqtt4homeassistant.data_classes import NO_STATE, ComponentConfig, ComponentState


if typing.TYPE_CHECKING:
    from ha_services.mqtt4homeassistant.device import MqttDevice


class Sensor(BaseComponent):
    """
    MQTT Sensor component for Home Assistant.
    https://www.home-assistant.io/integrations/sensor.mqtt/
    """

    def __init__(
        self,
        *,
        device: 'MqttDevice',
        name: str,
        uid: str,
        component: str = 'sensor',
        initial_state=NO_STATE,  # set_state() must be called to set the value
        #
        # https://www.home-assistant.io/integrations/sensor/#device-class
        device_class: str | None = None,  # e.g.: 'temperature'
        #
        # https://developers.home-assistant.io/docs/core/entity/sensor/#available-state-classes
        state_class: str | None = None,  # e.g.: 'measurement'
        unit_of_measurement: str | None = None,  # e.g.: '°C' / 'W' etc.
        suggested_display_precision: int | None = None,
        #
        # Optional min/max validation of int/float values:
        min_value: int | float | None = None,
        max_value: int | float | None = None,
    ):
        super().__init__(
            device=device,
            name=name,
            uid=uid,
            component=component,
            initial_state=initial_state,
        )

        self.device_class = device_class
        self.state_class = state_class
        self.unit_of_measurement = unit_of_measurement
        self.suggested_display_precision = suggested_display_precision
        self.min_value = min_value
        self.max_value = max_value

    def validate_state(self, state: str):
        super().validate_state(state)

        if self.min_value is not None:
            if not isinstance(state, (int, float)):
                raise InvalidStateValue(component=self, error_msg=f'{state=} is not a number')
            if state < self.min_value:
                raise InvalidStateValue(component=self, error_msg=f'{state=} is smaller than {self.min_value=}')

        if self.max_value is not None:
            if not isinstance(state, (int, float)):
               raise InvalidStateValue(component=self, error_msg=f'{state=} is not a number')
            if state > self.max_value and self.uid != "raspberrypi-process_cpu_usage":
               raise InvalidStateValue(component=self, error_msg=f'{state=} is bigger than {self.max_value=}')


    def get_state(self) -> ComponentState:
        # e.g.: {'topic': 'homeassistant/sensor/My-device/Chip-Temperature/state', 'payload': '40'}
        return ComponentState(
            topic=f'{self.topic_prefix}/state',
            payload=self.state,
        )

    def get_config(self) -> ComponentConfig:
        payload = {
            'component': self.component,
            'device': self.device.get_mqtt_payload(),
            'device_class': self.device_class,  # e.g.: 'temperature'
            'name': self.name,
            'unique_id': self.uid,
            'unit_of_measurement': self.unit_of_measurement,
            'state_class': self.state_class,  # e.g.: 'measurement'
            'state_topic': f'{self.topic_prefix}/state',
            'json_attributes_topic': f'{self.topic_prefix}/attributes',
        }
        if self.suggested_display_precision is not None:
            payload['suggested_display_precision'] = self.suggested_display_precision
        return ComponentConfig(topic=f'{self.topic_prefix}/config', payload=payload)
