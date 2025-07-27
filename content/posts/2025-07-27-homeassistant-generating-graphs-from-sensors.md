+++
title = 'Home Assistant: Generating Dashboard Graphs From Sensors'
date = 2025-07-27
toc = true
tags = ["homeassistant", "sensors"]
summary = "Generating a dashboard full of graphs from all sensors with given attributes"
+++

Over time I've developed a reasonably useful to me home assistant dashboard of all temperature and humidity sensors around my house. This was built manually over time, and whenever I add or remove a sensor I would have to update the dashboard myself. Obviously, I never remember to do so until I want to see that data.

## Requirements
- Use the same sensor card graph I've had setup
- Fully automatically generated. If I bring a new temperature+humidity sensor online, it should automatically be added to the dashboard. No further interaction required.
- Display each sensor's Temperature and Humidity graphs next to each other
- Be simple and easy to maintain

It was surprisingly difficult to put together the pieces here to meet all requirements. I would have tolerated generating this dashboard sever side at startup, and in fact did consider writing some templating code to just generate the dashboard from all entities. In the end, I found [lovelace-auto-entities](https://github.com/thomasloven/lovelace-auto-entities) and leveraged that project.

## Broad strokes
Utilize auto-entities to select all sensors that have a `temperature` device class. Place each found entity in a sensor card with a line graph. Repeat for humidity.

For nice organization, place both auto-entities in a horizontal stack, and sort both the same way. Now each sensor has temperature and humidity lined up next to each other.

## Tricky part

Getting the sensor card to play nice with auto-entities. In order to define an individual card per found entity, you have to modify the filters section. While this works, I find it to be completely unintuitive. In my mind, I'm trying to display data at this point not filter data out.

Even more confusing, auto-entities has a card type, as well as a card_param argument. It seems like you should be able to directly configure a sensor per entity using these types, but no.

## Final, full dashboard


[![end result](/images/2025-07-27-hass-dashbaords/dashboard-result.png)](/images/2025-07-27-hass-dashbaords/dashboard-result.png)

```yaml
type: vertical-stack
cards:
  - show_current: true
    show_forecast: true
    type: weather-forecast
    entity: weather.forecast_home_2
    forecast_type: daily
  - type: horizontal-stack
    cards:
      - type: custom:auto-entities
        filter:
          include:
            - options:
                # The options section describes the card we want to display for
                # each discovered entity
                type: sensor
                graph: line
              # domain finds the sensor portion of sensor.mysensorname_temperature
              domain: sensor
              attributes:
                # device_class makes sure we grab the temperature sensor
                device_class: temperature
          exclude: []
        card:
          type: vertical-stack
        show_empty: true
        card_param: cards
      - type: custom:auto-entities
        filter:
          include:
            # The options section describes the card we want to display for
            # each discovered entity
            - options:
                type: sensor
                graph: line
              domain: sensor
              attributes:
                device_class: humidity
          exclude: []
        card:
          type: vertical-stack
        show_empty: true
        card_param: cards
```

## How to break this dashboard

If a sensors is ever added that does not also expose a humidity sensor, then this display will no longer be even. In theory, there should be a way to exclude or require a 1 - 1 mapping of temperature and humidity but I have not figured that out yet.
