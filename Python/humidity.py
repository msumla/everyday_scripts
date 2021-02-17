# create index.html with the following content:
#
#<head>
#        <meta http-equiv="refresh" content="60;url=index.html"/>
#        <title>Humidity</title>
#</head>
#<body>
#        <a href="humidity-Mon.html">humidity-Mon</a>
#        <a href="humidity-Tue.html">humidity-Tue</a>
#        <a href="humidity-Wed.html">humidity-Wed</a>
#        <a href="humidity-Thu.html">humidity-Thu</a>
#        <a href="humidity-Fri.html">humidity-Fri</a>
#        <a href="humidity-Sat.html">humidity-Sat</a>
#        <a href="humidity-Sun.html">humidity-Sun</a>
#
#        <iframe src="humidity-Wed.html" style=height:100%;width:100%;border:none;"/>
#</body>

# configure crontab with the following content
#
#*/15 * * * *    cd /home/pi/humidity; logfile=humidity-`date +\%a`.txt; webfile=humidity-`date +\%a`.html; find humidity-* -mtime +7 -exec rm {} \;; python3 /home/pi/humidity/humidity.py $logfile $webfile; sed -i "s/src=\"humidity-...\.html/src=\"$webfile/" index.html

import os
import sys
import json
import time
import Adafruit_DHT
import plotly.graph_objects as go
import plotly.offline as po
import plotly.express as px


DHT_SENSOR = Adafruit_DHT.DHT22
DHT_PIN = 4

humidity, temperature = Adafruit_DHT.read_retry(DHT_SENSOR, DHT_PIN)
today_date = time.strftime('%d.%m.%Y')
timestamp = time.strftime('%H:%M')
dayofweek = time.strftime('%a')

if sys.argv[1]:
        logfile = sys.argv[1]
else:
        logfile = 'humidity-%s.txt' % dayofweek

f = open(logfile, 'a+')

if humidity is not None and temperature is not None:
        f.write('{"timestamp": "%s", "temperature": %f, "humidity": %f}\n' % (timestamp, temperature, humidity))
else:
        f.write('{"timestamp": "%s", "temperature": "", "humidity": ""}\n' % timestamp)
        print("Failed to retrieve data from the sensor")

f.close()

# data
f = open(logfile, 'r')
data = f.readlines()
f.close()

timestamps = [ json.loads(i)['timestamp'] for i in data]
temperatures = [ json.loads(i)['temperature'] for i in data]
humidities = [ json.loads(i)['humidity'] for i in data]

# figure trace
fig = go.Figure(layout_yaxis_range=[15, 60])
fig.add_trace(go.Scatter(x=timestamps, y=humidities,
                mode='lines+markers',
                name='humidity',
                line=go.scatter.Line(color='yellow'),
                line_width=5,
                marker_size=10)
)

fig.add_trace(go.Scatter(x=timestamps, y=temperatures,
                mode='lines+markers',
                name='temperature',
                line=go.scatter.Line(color='green'),
                line_width=5,
                marker_size=10)
)

fig.update_layout(
        title='%s | %s | Last result: %s | %s%% | %s*C' % (today_date, dayofweek, timestamp, round(humidity, 1), round(temperature, 1)),
        font_size=20
)

if sys.argv[2]:
        webfile = sys.argv[2]
else:
        webfile = 'humidity-%s.html' % dayofweek

f = open(logfile, 'a+')

#po.plot(fig, show_link=True, filename='index.html', image_filename='1', image='svg')
po.plot(fig, show_link=True, filename=webfile)
