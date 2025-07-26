import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MaterialApp(
    home: TrafficHomePage(),
    debugShowCheckedModeBanner: false,
  ));
}

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
    {"name": "Areacode", "lat": 11.1874, "lng": 76.0594}
  ];

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
      markers.add(Marker(
        markerId: MarkerId(loc["name"]),
        position: LatLng(loc["lat"], loc["lng"]),
        infoWindow: InfoWindow(title: loc["name"]),
      ));
    }
    setState(() {
      _markers = markers;
    });
  }

  Future<void> drawRoute() async {
    final startLoc = locations.firstWhere((loc) => loc["name"] == selectedStart);
    final endLoc = locations.firstWhere((loc) => loc["name"] == selectedEnd);

    _routePoints = [
      LatLng(startLoc["lat"], startLoc["lng"]),
      LatLng(endLoc["lat"], endLoc["lng"])
    ];

    setState(() {
      _polylines = {
        Polyline(
          polylineId: PolylineId("route"),
          visible: true,
          points: _routePoints,
          color: Colors.blue,
          width: 5,
        ),
      };
    });

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        min(startLoc["lat"], endLoc["lat"]),
        min(startLoc["lng"], endLoc["lng"]),
      ),
      northeast: LatLng(
        max(startLoc["lat"], endLoc["lat"]),
        max(startLoc["lng"], endLoc["lng"]),
      ),
    );
    _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  Future<void> submitRoute() async {
    final response = await http.post(
      Uri.parse('http://127.0.0.1:8000/api/route/set/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({"start": selectedStart, "end": selectedEnd}),
    );

    await drawRoute();

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
    final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/status/'));

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      setState(() {
        _statusData = jsonData['junctions'];
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to fetch status")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kottakkal Smart Traffic System"),
        backgroundColor: Colors.green[800],
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
                            child: Text(loc["name"]),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
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
                            child: Text(loc["name"]),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: submitRoute,
                  child: const Text("Show Route"),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
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
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("Traffic Status:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _statusData.length,
              itemBuilder: (context, index) {
                final j = _statusData[index];
                return ListTile(
                  title: Text(j["name"]),
                  subtitle: Text(j["alert"]),
                  trailing: Text("${j["vehicle_count"]} vehicles"),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
