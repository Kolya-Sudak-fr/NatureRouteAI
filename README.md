# NatureRouteAI 🌿

NatureRouteAI is an iOS app for planning multi-day trips around real nature spots. Choose a city, trip length, transport mode, and the landscapes you enjoy; the app finds places and displays your itinerary on a map.

> **Project status:** MVP in progress. Places are sourced from OpenTripMap, and route segments are calculated with MapKit. Route generation is currently data-driven; LLM-powered suggestions are not implemented yet.

## Screenshots

| Home | Route planner | Map |
|:---:|:---:|:---:|
| ![NatureRouteAI home screen](docs/screenshots/home.png) | ![NatureRouteAI route planner](docs/screenshots/planner.png) | ![NatureRouteAI map](docs/screenshots/map.png) |

## What it can do

- Find nature spots near a city using selected preferences: mountains, forests, lakes, waterfalls, and national parks.
- Build a multi-day itinerary with adjustable trip length and places per day.
- Choose walking, cycling, or driving for route directions.
- Show places and available route segments on an interactive MapKit map.
- Open a route or an individual stop in Apple Maps or Google Maps.
- Save routes locally with SwiftData and continue through stops in order.
- Show progress and useful error messages when places or directions are unavailable.

## Tech stack

| Area | Technology |
| --- | --- |
| Language and UI | Swift, SwiftUI |
| Architecture | MVVM |
| Networking | URLSession, async/await, OpenTripMap API |
| Maps and directions | MapKit, CoreLocation |
| Local persistence | SwiftData |

## Getting started

1. Open `NatureRouteAI/NatureRouteAI.xcodeproj` in Xcode.
2. Configure an OpenTripMap API key in your local `NatureRouteAI/Services/Secrets.swift`. This local secrets file is ignored by Git. Never commit API keys or credentials.
3. Select the NatureRouteAI scheme and run the app on an available iOS simulator or device.

## Project structure

```text
NatureRouteAI/
├── Models/          Route, RouteDay, Place, NaturePreference, TransportMode
├── Services/        NetworkService, RouteGenerator, RouteNavigationLinks, AppError
└── Features/
    ├── Home/
    ├── RoutePlanner/
    ├── Map/
    └── Saved Routes/
```

## Current limitations and next steps

- Nature spots come from OpenTripMap; route directions depend on MapKit coverage and may be unavailable for some segments.
- External navigation services can limit the number of stops in one route link, so longer itineraries continue one stop at a time.
- LLM suggestions, food and facilities discovery, accommodation search, accounts, and cloud sync are future work.
- Automated test coverage and CI build checks are not yet part of this MVP.

## Data and credentials

Place data is provided by [OpenTripMap](https://opentripmap.io/product). You need your own API key to run the app. Keep credentials in local configuration and out of source control.
