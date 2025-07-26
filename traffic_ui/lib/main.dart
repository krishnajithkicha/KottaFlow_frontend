import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart'; // Add this package for loading indicator

void main() {
  runApp(
    const MaterialApp(
      home: TrafficHomePage(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

// --- How to set up a proxy endpoint in Django for Google Directions API ---
// 1. In your Django backend, create a view that receives origin, destination, and forwards the request to Google Directions API.
// 2. Example Django view:
//
// from django.http import JsonResponse
// import requests
//
// def directions_proxy(request):
//     origin = request.GET.get('origin')
//     destination = request.GET.get('destination')
//     key = 'YOUR_GOOGLE_MAPS_API_KEY'
//     url = f'https://maps.googleapis.com/maps/api/directions/json?origin={origin}&destination={destination}&key={key}'
//     response = requests.get(url)
//     return JsonResponse(response.json())
//
// 3. Add a URL pattern for this view, e.g. path('api/directions/', directions_proxy)
// 4. In your Flutter code, replace the Google API URL with your Django endpoint:
//
// final String url = 'http://127.0.0.1:8000/api/directions/?origin=${startLoc["lat"]},${startLoc["lng"]}&destination=${endLoc["lat"]},${endLoc["lng"]}';
//
// This will avoid CORS issues for web apps.

class TrafficHomePage extends StatefulWidget {
  const TrafficHomePage({super.key});

  @override
  State<TrafficHomePage> createState() => _TrafficHomePageState();
}

class _TrafficHomePageState extends State<TrafficHomePage> {
  late GoogleMapController _mapController;
  String? selectedStart;
  String? selectedEnd;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];
  List<dynamic> _statusData = [];

  final List<Map<String, dynamic>> locations = [
    {"name": "Kottakkal", "lat": 10.9946, "lng": 76.0021},
    {"name": "Puthanathani", "lat": 10.9632, "lng": 76.0127},
    {"name": "Edarikode", "lat": 11.0031, "lng": 76.0325},
    {"name": "Changuvetty", "lat": 10.9911, "lng": 76.0150},
    {"name": "Kadampuzha", "lat": 11.0315, "lng": 75.9900},
    {"name": "Valanchery", "lat": 10.8793, "lng": 76.0331},
    {"name": "Parappanangadi", "lat": 11.0485, "lng": 75.9276},
    {"name": "Tirur", "lat": 10.9134, "lng": 75.9254},
    {"name": "Ponnani", "lat": 10.7678, "lng": 75.9256},
    {"name": "Areacode", "lat": 11.1874, "lng": 76.0594},
  ];

  bool _loadingStatus = false;
  bool _loadingRoute = false;
  double? _routeDistance;
  int? _routeTime;

  // Add your Google Maps Directions API key here
  final String _googleMapsApiKey = 'AIzaSyCzPpjsrF--MkMLHaFLsHkxRPQxZohV10s';

  @override
  void initState() {
    super.initState();
    selectedStart = locations[0]['name'];
    selectedEnd = locations[1]['name'];
    _loadMarkers();
    fetchStatus();
  }

  void _loadMarkers() {
    Set<Marker> markers = {};
    for (var loc in locations) {
      markers.add(
        Marker(
          markerId: MarkerId(loc["name"]),
          position: LatLng(loc["lat"], loc["lng"]),
          infoWindow: InfoWindow(title: loc["name"]),
        ),
      );
    }
    setState(() {
      _markers = markers;
    });
  }

  // Corrected Bézier curve route calculation and polyline drawing
  Future<void> drawRoute() async {
    setState(() {
      _loadingRoute = true;
    });

    final startLoc = locations.firstWhere(
      (loc) => loc["name"] == selectedStart,
    );
    final endLoc = locations.firstWhere((loc) => loc["name"] == selectedEnd);

    LatLng p0 = LatLng(startLoc["lat"], startLoc["lng"]);
    LatLng p2 = LatLng(endLoc["lat"], endLoc["lng"]);
    // Control point: offset from midpoint for curve
    double controlLat = (p0.latitude + p2.latitude) / 2 + 0.03;
    double controlLng = (p0.longitude + p2.longitude) / 2 - 0.03;
    LatLng p1 = LatLng(controlLat, controlLng);

    List<LatLng> curvePoints = [];
    int steps = 50;
    for (int i = 0; i <= steps; i++) {
      double t = i / steps;
      double lat =
          (1 - t) * (1 - t) * p0.latitude +
          2 * (1 - t) * t * p1.latitude +
          t * t * p2.latitude;
      double lng =
          (1 - t) * (1 - t) * p0.longitude +
          2 * (1 - t) * t * p1.longitude +
          t * t * p2.longitude;
      curvePoints.add(LatLng(lat, lng));
    }

    double distance =
        sqrt(
          pow(p0.latitude - p2.latitude, 2) +
              pow(p0.longitude - p2.longitude, 2),
        ) *
        111;
    int time = (distance / 40 * 60).round(); // Assume avg speed 40km/h

    setState(() {
      _polylines = {
        Polyline(
          polylineId: PolylineId("route"),
          visible: true,
          points: curvePoints,
          color: Colors.blue,
          width: 5,
        ),
      };
      _routePoints = curvePoints;
      _routeDistance = distance;
      _routeTime = time;
      _loadingRoute = false;
    });

    LatLngBounds bounds = _getBounds(curvePoints);
    _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  // Polyline decoding helper (not used for Bézier, but keep for future API use)
  List<LatLng> _decodePolyline(String polyline) {
    List<LatLng> points = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // Helper to get bounds from route points
  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> submitRoute() async {
    setState(() {
      _loadingRoute = true;
    });
    final response = await http.post(
      Uri.parse('http://127.0.0.1:8000/api/route/set/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({"start": selectedStart, "end": selectedEnd}),
    );

    await drawRoute();

    setState(() {
      _loadingRoute = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.statusCode == 200
              ? 'Route submitted and drawn successfully'
              : 'Failed to submit route',
        ),
      ),
    );
  }

  Future<void> fetchStatus() async {
    setState(() {
      _loadingStatus = true;
    });
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/status/'),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        setState(() {
          _statusData = jsonData['junctions'];
          _loadingStatus = false;
        });
      } else {
        setState(() {
          _loadingStatus = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to fetch status")));
      }
    } catch (e) {
      setState(() {
        _loadingStatus = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Error fetching status")));
    }
  }

  void _centerRoute() {
    if (_routePoints.isNotEmpty) {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          min(_routePoints.first.latitude, _routePoints.last.latitude),
          min(_routePoints.first.longitude, _routePoints.last.longitude),
        ),
        northeast: LatLng(
          max(_routePoints.first.latitude, _routePoints.last.latitude),
          max(_routePoints.first.longitude, _routePoints.last.longitude),
        ),
      );
      _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kottakkal Smart Traffic System"),
        backgroundColor: Colors.green[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Traffic Status",
            onPressed: fetchStatus,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.grey[200],
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.green),
                    const SizedBox(width: 4),
                    const Text("Start: "),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: selectedStart,
                        isExpanded: true,
                        onChanged: (value) {
                          setState(() {
                            selectedStart = value;
                          });
                        },
                        items: locations.map((loc) {
                          return DropdownMenuItem<String>(
                            value: loc["name"],
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(loc["name"]),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.red),
                    const SizedBox(width: 4),
                    const Text("End: "),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: selectedEnd,
                        isExpanded: true,
                        onChanged: (value) {
                          setState(() {
                            selectedEnd = value;
                          });
                        },
                        items: locations.map((loc) {
                          return DropdownMenuItem<String>(
                            value: loc["name"],
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(loc["name"]),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _loadingRoute ? null : submitRoute,
                  icon: const Icon(Icons.route),
                  label: const Text("Show Route"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                  ),
                ),
                if (_loadingRoute)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SpinKitCircle(color: Colors.green, size: 32),
                  ),
                if (_routeDistance != null && _routeTime != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Card(
                      color: Colors.green[50],
                      child: ListTile(
                        leading: const Icon(
                          Icons.directions_car,
                          color: Colors.green,
                        ),
                        title: Text(
                          "Distance: ${_routeDistance!.toStringAsFixed(2)} km",
                        ),
                        subtitle: Text("Estimated Time: $_routeTime min"),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(10.9946, 76.0021),
                    zoom: 12,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    backgroundColor: Colors.green[700],
                    child: const Icon(Icons.center_focus_strong),
                    tooltip: "Center Route",
                    onPressed: _centerRoute,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              "Traffic Status:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: _loadingStatus
                ? const Center(
                    child: SpinKitFadingCircle(color: Colors.green, size: 40),
                  )
                : ListView.builder(
                    itemCount: _statusData.length,
                    itemBuilder: (context, index) {
                      final j = _statusData[index];
                      Color alertColor;
                      IconData alertIcon;
                      switch (j["alert"]) {
                        case "Heavy":
                          alertColor = Colors.red;
                          alertIcon = Icons.warning;
                          break;
                        case "Moderate":
                          alertColor = Colors.orange;
                          alertIcon = Icons.error_outline;
                          break;
                        default:
                          alertColor = Colors.green;
                          alertIcon = Icons.check_circle;
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: Icon(alertIcon, color: alertColor),
                          title: Text(
                            j["name"],
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            j["alert"],
                            style: TextStyle(color: alertColor),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.directions_car, size: 18),
                              const SizedBox(width: 4),
                              Text("${j["vehicle_count"]} vehicles"),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
