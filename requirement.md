
# CoRides - AI-Assisted Ride Booking & Sharing (MVP)

## 1. Project Overview

CoRides is a Flutter-based ride-sharing application that uses Gemini 3 as an active orchestration agent. Unlike traditional apps, users negotiate rides via voice/text, and the AI matches Riders with Drivers based on multi-stop route proximity and negotiated prices.

## 2. Technical Stack

-   Frontend: Flutter (Mobile). Reference lib/main.dart for existing UI.
    
-   Backend: Firebase (Blaze Plan suggested for Cloud Functions).
    

-   Auth: Firebase Phone Authentication.
    
-   Database: Cloud Firestore.
    
-   Logic: Firebase Cloud Functions (Node.js/Python).
    

-   AI Engine: Google Gemini 3 API (Flash/Pro).
    
-   Maps: Google Maps SDK (Flutter) & Places API.
    

## 3. Database Schema (Firestore)

Implement the following collections. Use snake_case for field names.

### users

-   uid (String, PK)
    
-   phone_number (String)
    
-   role (String: 'rider' | 'driver')
    
-   wallet_balance (Number, default: 0)
    
-   created_at (Timestamp)
    

### rides (Active Requests & Offers)

-   ride_id (String, PK)
    
-   creator_id (String, FK -> users.uid)
    
-   type (String: 'request' | 'offer')
    
-   origin (GeoPoint + Address String)
    
-   destination (GeoPoint + Address String)
    
-   waypoints (Array of GeoPoints - Driver Only)
    
-   departure_time (Timestamp)
    
-   status (String: 'pending', 'matched', 'ongoing', 'completed', 'cancelled')
    
-   negotiated_price (Number)
    
-   seats_available (Number)
    

### messages (AI Context & Chat History)

-   message_id (String, PK)
    
-   user_id (String, FK)
    
-   timestamp (Timestamp)
    
-   is_user_message (Boolean)
    
-   content (String - Transcript or AI Response)
    
-   intent_extracted (Map/JSON - e.g., {'dest': 'F6', 'price': 500})
    

### payments (Ledger Record)

-   transaction_id (String, PK)
    
-   ride_id (String, FK)
    
-   payer_id (String, FK)
    
-   payee_id (String, FK)
    
-   amount (Number)
    
-   method (String: 'cash', 'wallet')
    
-   status (String: 'completed')
    

## 

----------

4. Feature Requirements & Logic

### A. Authentication & Onboarding

-   Phone Auth: Users sign in with OTP.
    
-   Profile Creation: On first login, create a user document. Default role is "Rider".
    

### B. AI-Assisted Booking (The "Active Agent")

-   Interface: Triggered via the "Gemini Button" (FAB). Opens AIAssistSheet.
    
-   Slot-Filling Logic:
    

1.  User speaks/types.
    
2.  Gemini System Instruction: "You are a ride coordinator. You MUST extract: origin, destination, time, and price. If any field is missing, ask the user specifically for it."
    
3.  Loop: Keep the conversation active until all fields are present.
    
4.  Completion: When complete, Gemini outputs a JSON block. The App parses this and creates a document in rides (status: 'pending').
    

### C. Multi-Stop Route Matching (Driver Logic)

-   Driver Input: Drivers can set an origin, destination, and add multiple waypoints (stops).
    
-   Matching Algorithm (Cloud Function / Local Logic):
    

-   Trigger: When a ride (request) is created.
    
-   Logic: Query all active rides (type: 'offer').
    
-   Geo-Calculation: Check if the Rider's origin AND destination are within a 2km radius of the Driver's route (polyline) or any specific waypoint.
    
-   Result: Return a list of "Compatible Drivers" sorted by Price and Proximity.
    

### D. Message History

-   Store every interaction from the AIAssistSheet into the messages collection.
    
-   Display this history in the "Messages" tab (Bottom Nav).
    

### E. Wallet & Payments

-   No Real Gateway: Implement a "Ledger System".
    
-   Action: When a ride is marked 'completed', create a payment record.
    
-   UI: Update the "Wallet" display in the Drawer to reflect the sum of payments (Credit for Driver, Debit for Rider).
    

## 

----------

5. UI/UX Guidelines

-   Style: Use the existing design in lib/main.dart (Material 3, Floating Action Button, Bottom Sheet).
    
-   Map: The Home Screen background must be a Google Map. Markers should show:
    

-   Current User Location (Blue Dot).
    
-   Nearby Available Drivers (Car Icons).
    
-   Route Polyline (when a ride is active).
    

## 6. Implementation Steps (For Antigravity Agent)

1.  Setup: Initialize Firebase Project & CLI.
    
2.  Backend: Deploy Firestore Rules & Cloud Functions.
    
3.  Core Services: Implement AuthService and GeminiService.
    
4.  Wiring: Connect lib/main.dart UI components to the Services.
    
5.  Verification: Test the "Voice -> AI -> Firestore" loop.