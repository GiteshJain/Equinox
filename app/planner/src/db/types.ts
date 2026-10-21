
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "public": {
          Tables: {
            "aircraft": {
                  Row: {
                    "aircraft_type_id": number | null,"airline_id": number,"base_code": string | null,"cabin_config_id": number | null,"checked_on": string | null,"created_at": string,"delivery_at": string | null,"extra": NonNullable<Json>,"id": number,"maintenance_note": string | null,"order_base_code": string | null,"order_config_id": number | null,"order_note": string | null,"ordered_on": string | null,"registration": string,"retired_on": string | null,"schedule_changed_on": string | null,"status": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_type_id"?: number | null,"airline_id": number,"base_code"?: string | null,"cabin_config_id"?: number | null,"checked_on"?: string | null,"created_at"?: string,"delivery_at"?: string | null,"extra"?: NonNullable<Json>,"id"?: never,"maintenance_note"?: string | null,"order_base_code"?: string | null,"order_config_id"?: number | null,"order_note"?: string | null,"ordered_on"?: string | null,"registration": string,"retired_on"?: string | null,"schedule_changed_on"?: string | null,"status": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_type_id"?: number | null,"airline_id"?: number,"base_code"?: string | null,"cabin_config_id"?: number | null,"checked_on"?: string | null,"created_at"?: string,"delivery_at"?: string | null,"extra"?: NonNullable<Json>,"id"?: never,"maintenance_note"?: string | null,"order_base_code"?: string | null,"order_config_id"?: number | null,"order_note"?: string | null,"ordered_on"?: string | null,"registration"?: string,"retired_on"?: string | null,"schedule_changed_on"?: string | null,"status"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "aircraft_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "aircraft_base_code_fkey"
      columns: ["base_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "aircraft_config_fkey"
      columns: ["cabin_config_id","world_id"]
isOneToOne: false
      referencedRelation: "cabin_configs"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "aircraft_order_base_code_fkey"
      columns: ["order_base_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "aircraft_order_config_fkey"
      columns: ["order_config_id","world_id"]
isOneToOne: false
      referencedRelation: "cabin_configs"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "aircraft_type_fkey"
      columns: ["aircraft_type_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft_types"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "aircraft_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"aircraft_cabin_keeps": {
                  Row: {
                    "aircraft_id": number,"cabin": string,"created_at": string,"decided_on": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": number,"cabin": string,"created_at"?: string,"decided_on"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_id"?: number,"cabin"?: string,"created_at"?: string,"decided_on"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "aircraft_cabin_keeps_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "aircraft_cabin_keeps_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"aircraft_types": {
                  Row: {
                    "created_at": string,"cruise_kmh": number | null,"family_no": number | null,"gap_target_h": number | null,"ground_keep_min": number | null,"id": number,"maint_per_cycle": number | null,"maint_per_hour": number | null,"min_turn_min": number | null,"name": string,"order_config_id": number | null,"price": number | null,"range_km": number | null,"seats_max": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"cruise_kmh"?: number | null,"family_no"?: number | null,"gap_target_h"?: number | null,"ground_keep_min"?: number | null,"id"?: never,"maint_per_cycle"?: number | null,"maint_per_hour"?: number | null,"min_turn_min"?: number | null,"name": string,"order_config_id"?: number | null,"price"?: number | null,"range_km"?: number | null,"seats_max"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "created_at"?: string,"cruise_kmh"?: number | null,"family_no"?: number | null,"gap_target_h"?: number | null,"ground_keep_min"?: number | null,"id"?: never,"maint_per_cycle"?: number | null,"maint_per_hour"?: number | null,"min_turn_min"?: number | null,"name"?: string,"order_config_id"?: number | null,"price"?: number | null,"range_km"?: number | null,"seats_max"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "aircraft_types_order_config_fkey"
      columns: ["order_config_id","world_id"]
isOneToOne: false
      referencedRelation: "cabin_configs"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "aircraft_types_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"airline_aircraft_types": {
                  Row: {
                    "aircraft_type_id": number,"airline_id": number,"created_at": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_type_id": number,"airline_id": number,"created_at"?: string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_type_id"?: number,"airline_id"?: number,"created_at"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "airline_aircraft_types_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_aircraft_types_type_fkey"
      columns: ["aircraft_type_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft_types"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_aircraft_types_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"airline_bases": {
                  Row: {
                    "airline_id": number,"airport_code": string,"bank_times": (string)[] | null,"created_at": string,"flight_no_from": number | null,"hold_note": string | null,"id": number,"is_main": boolean,"last_flight_no": number | null,"parent_base_id": number | null,"position": number | null,"role": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"airport_code": string,"bank_times"?: (string)[] | null,"created_at"?: string,"flight_no_from"?: number | null,"hold_note"?: string | null,"id"?: never,"is_main"?: boolean,"last_flight_no"?: number | null,"parent_base_id"?: number | null,"position"?: number | null,"role": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"airport_code"?: string,"bank_times"?: (string)[] | null,"created_at"?: string,"flight_no_from"?: number | null,"hold_note"?: string | null,"id"?: never,"is_main"?: boolean,"last_flight_no"?: number | null,"parent_base_id"?: number | null,"position"?: number | null,"role"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "airline_bases_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_bases_airport_code_fkey"
      columns: ["airport_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "airline_bases_parent_fkey"
      columns: ["parent_base_id","world_id"]
isOneToOne: false
      referencedRelation: "airline_bases"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_bases_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"airline_days": {
                  Row: {
                    "aircraft_by_type": Json | null,"aircraft_total": number | null,"airline_id": number,"cash": number | null,"cash_at": string | null,"complete": boolean,"day": string,"destinations": number | null,"eco_load_pct": number | null,"fixed_next7": number | null,"flight_costs": number | null,"flight_profit": number | null,"flights_flown": number | null,"leases_paid": number | null,"load_pct": number | null,"on_order": number | null,"passengers": number | null,"purchases_paid": number | null,"revenue": number | null,"salaries_paid": number | null,"seats_flown": number | null,"source": string,"taken_at": string,"weekly_departures": number | null,"weekly_seats": number | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_by_type"?: Json | null,"aircraft_total"?: number | null,"airline_id": number,"cash"?: number | null,"cash_at"?: string | null,"complete"?: boolean,"day": string,"destinations"?: number | null,"eco_load_pct"?: number | null,"fixed_next7"?: number | null,"flight_costs"?: number | null,"flight_profit"?: number | null,"flights_flown"?: number | null,"leases_paid"?: number | null,"load_pct"?: number | null,"on_order"?: number | null,"passengers"?: number | null,"purchases_paid"?: number | null,"revenue"?: number | null,"salaries_paid"?: number | null,"seats_flown"?: number | null,"source": string,"taken_at": string,"weekly_departures"?: number | null,"weekly_seats"?: number | null,"world_id": number
                  }
                  Update: {
                    "aircraft_by_type"?: Json | null,"aircraft_total"?: number | null,"airline_id"?: number,"cash"?: number | null,"cash_at"?: string | null,"complete"?: boolean,"day"?: string,"destinations"?: number | null,"eco_load_pct"?: number | null,"fixed_next7"?: number | null,"flight_costs"?: number | null,"flight_profit"?: number | null,"flights_flown"?: number | null,"leases_paid"?: number | null,"load_pct"?: number | null,"on_order"?: number | null,"passengers"?: number | null,"purchases_paid"?: number | null,"revenue"?: number | null,"salaries_paid"?: number | null,"seats_flown"?: number | null,"source"?: string,"taken_at"?: string,"weekly_departures"?: number | null,"weekly_seats"?: number | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "airline_days_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_days_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"airline_order_cabins": {
                  Row: {
                    "aircraft_type_id": number,"airline_id": number,"created_at": string,"order_config_id": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_type_id": number,"airline_id": number,"created_at"?: string,"order_config_id"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_type_id"?: number,"airline_id"?: number,"created_at"?: string,"order_config_id"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "airline_order_cabins_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_order_cabins_config_fkey"
      columns: ["order_config_id","world_id"]
isOneToOne: false
      referencedRelation: "cabin_configs"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_order_cabins_type_fkey"
      columns: ["aircraft_type_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft_types"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airline_order_cabins_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"airlines": {
                  Row: {
                    "active": boolean,"blurb": string | null,"country_code": string | null,"created_at": string,"founded_on": string | null,"game_id": number,"game_name": string | null,"group_id": number | null,"home_airport_code": string | null,"iata_code": string | null,"id": number,"is_lcc": boolean,"livery_color": string | null,"low_demand": boolean,"photo_city": string | null,"planner_name": string | null,"position": number | null,"public_name": string | null,"region_text": string | null,"role_text": string | null,"slug": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"blurb"?: string | null,"country_code"?: string | null,"created_at"?: string,"founded_on"?: string | null,"game_id": number,"game_name"?: string | null,"group_id"?: number | null,"home_airport_code"?: string | null,"iata_code"?: string | null,"id"?: never,"is_lcc"?: boolean,"livery_color"?: string | null,"low_demand"?: boolean,"photo_city"?: string | null,"planner_name"?: string | null,"position"?: number | null,"public_name"?: string | null,"region_text"?: string | null,"role_text"?: string | null,"slug"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "active"?: boolean,"blurb"?: string | null,"country_code"?: string | null,"created_at"?: string,"founded_on"?: string | null,"game_id"?: number,"game_name"?: string | null,"group_id"?: number | null,"home_airport_code"?: string | null,"iata_code"?: string | null,"id"?: never,"is_lcc"?: boolean,"livery_color"?: string | null,"low_demand"?: boolean,"photo_city"?: string | null,"planner_name"?: string | null,"position"?: number | null,"public_name"?: string | null,"region_text"?: string | null,"role_text"?: string | null,"slug"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "airlines_country_code_fkey"
      columns: ["country_code"]
isOneToOne: false
      referencedRelation: "countries"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "airlines_group_fkey"
      columns: ["group_id","world_id"]
isOneToOne: false
      referencedRelation: "groups"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "airlines_home_airport_code_fkey"
      columns: ["home_airport_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "airlines_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"airports": {
                  Row: {
                    "city": string | null,"code": string,"country_code": string | null,"created_at": string,"lat": number | null,"lon": number | null,"updated_at": string,"utc_offset": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "city"?: string | null,"code": string,"country_code"?: string | null,"created_at"?: string,"lat"?: number | null,"lon"?: number | null,"updated_at"?: string,"utc_offset"?: number | null
                  }
                  Update: {
                    "city"?: string | null,"code"?: string,"country_code"?: string | null,"created_at"?: string,"lat"?: number | null,"lon"?: number | null,"updated_at"?: string,"utc_offset"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "airports_country_code_fkey"
      columns: ["country_code"]
isOneToOne: false
      referencedRelation: "countries"
      referencedColumns: ["code"]
    }
                  ]
                },"cabin_configs": {
                  Row: {
                    "aircraft_type_id": number | null,"business_seats": number | null,"cabin": string | null,"code": string,"cost": number | null,"created_at": string,"economy_seats": number | null,"id": number,"note": string | null,"seats": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_type_id"?: number | null,"business_seats"?: number | null,"cabin"?: string | null,"code": string,"cost"?: number | null,"created_at"?: string,"economy_seats"?: number | null,"id"?: never,"note"?: string | null,"seats"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_type_id"?: number | null,"business_seats"?: number | null,"cabin"?: string | null,"code"?: string,"cost"?: number | null,"created_at"?: string,"economy_seats"?: number | null,"id"?: never,"note"?: string | null,"seats"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "cabin_configs_type_fkey"
      columns: ["aircraft_type_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft_types"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "cabin_configs_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"capture_keys": {
                  Row: {
                    "created_at": string | null,"id": number,"key_hash": string,"label": string | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string | null,"id"?: number,"key_hash": string,"label"?: string | null,"world_id": number
                  }
                  Update: {
                    "created_at"?: string | null,"id"?: number,"key_hash"?: string,"label"?: string | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "capture_keys_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"cash_entries": {
                  Row: {
                    "airline_id": number,"cash": number | null,"created_at": string,"day": string,"entered_at": string | null,"fixed_next7": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"cash"?: number | null,"created_at"?: string,"day": string,"entered_at"?: string | null,"fixed_next7"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"cash"?: number | null,"created_at"?: string,"day"?: string,"entered_at"?: string | null,"fixed_next7"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "cash_entries_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "cash_entries_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"change_log": {
                  Row: {
                    "actor": string,"actor_detail": string | null,"changed_at": string,"db_role": string | null,"id": number,"new_values": Json | null,"old_values": Json | null,"op": string,"row_key": NonNullable<Json>,"table_name": string,"txid": number | null,"world_id": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "actor": string,"actor_detail"?: string | null,"changed_at"?: string,"db_role"?: string | null,"id"?: never,"new_values"?: Json | null,"old_values"?: Json | null,"op": string,"row_key": NonNullable<Json>,"table_name": string,"txid"?: number | null,"world_id"?: number | null
                  }
                  Update: {
                    "actor"?: string,"actor_detail"?: string | null,"changed_at"?: string,"db_role"?: string | null,"id"?: never,"new_values"?: Json | null,"old_values"?: Json | null,"op"?: string,"row_key"?: NonNullable<Json>,"table_name"?: string,"txid"?: number | null,"world_id"?: number | null
                  }
                  Relationships: [
                    
                  ]
                },"countries": {
                  Row: {
                    "code": string,"created_at": string,"name": string,"region": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"created_at"?: string,"name": string,"region"?: string,"updated_at"?: string
                  }
                  Update: {
                    "code"?: string,"created_at"?: string,"name"?: string,"region"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"dismissals": {
                  Row: {
                    "alert_key": string,"created_at": string,"dismissed_on": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "alert_key": string,"created_at"?: string,"dismissed_on"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "alert_key"?: string,"created_at"?: string,"dismissed_on"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "dismissals_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"fare_plan": {
                  Row: {
                    "airline_id": number,"cabin_class": string | null,"change_pct": number | null,"created_at": string,"extra": NonNullable<Json>,"fare_from": number | null,"id": number,"ladder_move": string | null,"legacy_key": string | null,"level_pct": number | null,"proposed_on": string | null,"reason": string | null,"route_id": number | null,"status": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"cabin_class"?: string | null,"change_pct"?: number | null,"created_at"?: string,"extra"?: NonNullable<Json>,"fare_from"?: number | null,"id"?: never,"ladder_move"?: string | null,"legacy_key"?: string | null,"level_pct"?: number | null,"proposed_on"?: string | null,"reason"?: string | null,"route_id"?: number | null,"status": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"cabin_class"?: string | null,"change_pct"?: number | null,"created_at"?: string,"extra"?: NonNullable<Json>,"fare_from"?: number | null,"id"?: never,"ladder_move"?: string | null,"legacy_key"?: string | null,"level_pct"?: number | null,"proposed_on"?: string | null,"reason"?: string | null,"route_id"?: number | null,"status"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "fare_plan_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "fare_plan_route_fkey"
      columns: ["route_id","world_id"]
isOneToOne: false
      referencedRelation: "routes"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "fare_plan_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"flight_legs": {
                  Row: {
                    "aircraft_id": number | null,"airline_id": number,"block_min": number | null,"created_at": string,"days_utc": (number)[],"dep_utc_min": number | null,"dest_code": string,"flight_no": number | null,"id": number,"leg_no": number,"origin_code": string,"rotation_id": number,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id"?: number | null,"airline_id": number,"block_min"?: number | null,"created_at"?: string,"days_utc": (number)[],"dep_utc_min"?: number | null,"dest_code": string,"flight_no"?: number | null,"id"?: never,"leg_no": number,"origin_code": string,"rotation_id": number,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_id"?: number | null,"airline_id"?: number,"block_min"?: number | null,"created_at"?: string,"days_utc"?: (number)[],"dep_utc_min"?: number | null,"dest_code"?: string,"flight_no"?: number | null,"id"?: never,"leg_no"?: number,"origin_code"?: string,"rotation_id"?: number,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "flight_legs_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "flight_legs_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "flight_legs_dest_code_fkey"
      columns: ["dest_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "flight_legs_origin_code_fkey"
      columns: ["origin_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "flight_legs_rotation_fkey"
      columns: ["rotation_id","airline_id"]
isOneToOne: false
      referencedRelation: "rotations"
      referencedColumns: ["id","airline_id"]
    },{
      foreignKeyName: "flight_legs_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_balance": {
                  Row: {
                    "account": string,"airline": string,"airline_id": number,"amount": number | null,"capture_day": string,"captured_at": string | null,"captured_on": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "account": string,"airline": string,"airline_id": number,"amount"?: number | null,"capture_day": string,"captured_at"?: string | null,"captured_on": string,"world_id": number
                  }
                  Update: {
                    "account"?: string,"airline"?: string,"airline_id"?: number,"amount"?: number | null,"capture_day"?: string,"captured_at"?: string | null,"captured_on"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_balance_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_balance_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_capture_raw": {
                  Row: {
                    "airline": string,"airline_id": number,"captured_at": string,"id": number,"kind": string,"page_url": string | null,"rows": NonNullable<Json>,"verdict": string | null,"verdict_facts": Json | null,"verdict_note": string | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline": string,"airline_id": number,"captured_at"?: string,"id"?: number,"kind": string,"page_url"?: string | null,"rows": NonNullable<Json>,"verdict"?: string | null,"verdict_facts"?: Json | null,"verdict_note"?: string | null,"world_id": number
                  }
                  Update: {
                    "airline"?: string,"airline_id"?: number,"captured_at"?: string,"id"?: number,"kind"?: string,"page_url"?: string | null,"rows"?: NonNullable<Json>,"verdict"?: string | null,"verdict_facts"?: Json | null,"verdict_note"?: string | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_capture_raw_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_capture_raw_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_events": {
                  Row: {
                    "airline": string,"airline_id": number,"balance": number | null,"captured_at": string | null,"credit": number | null,"debit": number | null,"descr": string,"due_at": string | null,"event_date": string,"event_time": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline": string,"airline_id": number,"balance"?: number | null,"captured_at"?: string | null,"credit"?: number | null,"debit"?: number | null,"descr": string,"due_at"?: string | null,"event_date": string,"event_time": string,"world_id": number
                  }
                  Update: {
                    "airline"?: string,"airline_id"?: number,"balance"?: number | null,"captured_at"?: string | null,"credit"?: number | null,"debit"?: number | null,"descr"?: string,"due_at"?: string | null,"event_date"?: string,"event_time"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_events_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_events_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_flights": {
                  Row: {
                    "aircraft_id": number | null,"airline_id": number,"arr_at": string | null,"arr_local": string | null,"atc": number | null,"bus_fare": number | null,"bus_pax": number | null,"bus_pct": number | null,"bus_seats": number | null,"cargo_cap": number | null,"cargo_income": number | null,"cargo_pct": number | null,"cargo_rate": number | null,"cargo_units": number | null,"cost_total": number | null,"created_at": string,"dep_at": string | null,"dep_local": string | null,"dest_code": string | null,"eco_fare": number | null,"eco_pax": number | null,"eco_pct": number | null,"eco_seats": number | null,"flight_no": number | null,"fst_fare": number | null,"fst_pax": number | null,"fst_pct": number | null,"fst_seats": number | null,"fuel": number | null,"game_date": string | null,"handling": number | null,"id": number,"income_total": number | null,"landing": number | null,"loads_captured_at": string | null,"maint_registration": string | null,"maintenance": number | null,"money_captured_at": string | null,"onboard": number | null,"origin_code": string | null,"pax_income": number | null,"posted_at": string | null,"profit": number | null,"registration": string | null,"route_id": number | null,"statement_blk": number | null,"statement_pax": number | null,"statement_routes": number | null,"status": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id"?: number | null,"airline_id": number,"arr_at"?: string | null,"arr_local"?: string | null,"atc"?: number | null,"bus_fare"?: number | null,"bus_pax"?: number | null,"bus_pct"?: number | null,"bus_seats"?: number | null,"cargo_cap"?: number | null,"cargo_income"?: number | null,"cargo_pct"?: number | null,"cargo_rate"?: number | null,"cargo_units"?: number | null,"cost_total"?: number | null,"created_at"?: string,"dep_at"?: string | null,"dep_local"?: string | null,"dest_code"?: string | null,"eco_fare"?: number | null,"eco_pax"?: number | null,"eco_pct"?: number | null,"eco_seats"?: number | null,"flight_no"?: number | null,"fst_fare"?: number | null,"fst_pax"?: number | null,"fst_pct"?: number | null,"fst_seats"?: number | null,"fuel"?: number | null,"game_date"?: string | null,"handling"?: number | null,"id"?: never,"income_total"?: number | null,"landing"?: number | null,"loads_captured_at"?: string | null,"maint_registration"?: string | null,"maintenance"?: number | null,"money_captured_at"?: string | null,"onboard"?: number | null,"origin_code"?: string | null,"pax_income"?: number | null,"posted_at"?: string | null,"profit"?: never,"registration"?: string | null,"route_id"?: number | null,"statement_blk"?: number | null,"statement_pax"?: number | null,"statement_routes"?: number | null,"status"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_id"?: number | null,"airline_id"?: number,"arr_at"?: string | null,"arr_local"?: string | null,"atc"?: number | null,"bus_fare"?: number | null,"bus_pax"?: number | null,"bus_pct"?: number | null,"bus_seats"?: number | null,"cargo_cap"?: number | null,"cargo_income"?: number | null,"cargo_pct"?: number | null,"cargo_rate"?: number | null,"cargo_units"?: number | null,"cost_total"?: number | null,"created_at"?: string,"dep_at"?: string | null,"dep_local"?: string | null,"dest_code"?: string | null,"eco_fare"?: number | null,"eco_pax"?: number | null,"eco_pct"?: number | null,"eco_seats"?: number | null,"flight_no"?: number | null,"fst_fare"?: number | null,"fst_pax"?: number | null,"fst_pct"?: number | null,"fst_seats"?: number | null,"fuel"?: number | null,"game_date"?: string | null,"handling"?: number | null,"id"?: never,"income_total"?: number | null,"landing"?: number | null,"loads_captured_at"?: string | null,"maint_registration"?: string | null,"maintenance"?: number | null,"money_captured_at"?: string | null,"onboard"?: number | null,"origin_code"?: string | null,"pax_income"?: number | null,"posted_at"?: string | null,"profit"?: never,"registration"?: string | null,"route_id"?: number | null,"statement_blk"?: number | null,"statement_pax"?: number | null,"statement_routes"?: number | null,"status"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_flights_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_flights_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_flights_route_fkey"
      columns: ["route_id","world_id"]
isOneToOne: false
      referencedRelation: "routes"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_flights_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_payments": {
                  Row: {
                    "aircraft_id": number | null,"airline_id": number,"amount": number,"created_at": string,"descr": string,"id": number,"kind": string,"occ": number,"paid_at": string,"registration": string | null,"side": string,"statement_blk": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id"?: number | null,"airline_id": number,"amount": number,"created_at"?: string,"descr": string,"id"?: never,"kind": string,"occ": number,"paid_at": string,"registration"?: string | null,"side": string,"statement_blk"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_id"?: number | null,"airline_id"?: number,"amount"?: number,"created_at"?: string,"descr"?: string,"id"?: never,"kind"?: string,"occ"?: number,"paid_at"?: string,"registration"?: string | null,"side"?: string,"statement_blk"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_payments_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_payments_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_payments_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_pnl": {
                  Row: {
                    "airline": string,"airline_id": number,"capture_day": string,"captured_at": string | null,"captured_on": string,"current_p": number | null,"last_p": number | null,"line": string,"total_p": number | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline": string,"airline_id": number,"capture_day": string,"captured_at"?: string | null,"captured_on": string,"current_p"?: number | null,"last_p"?: number | null,"line": string,"total_p"?: number | null,"world_id": number
                  }
                  Update: {
                    "airline"?: string,"airline_id"?: number,"capture_day"?: string,"captured_at"?: string | null,"captured_on"?: string,"current_p"?: number | null,"last_p"?: number | null,"line"?: string,"total_p"?: number | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_pnl_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_pnl_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_scan_airlines": {
                  Row: {
                    "airline_id": number,"enterprise_id": number,"n_airports": number | null,"n_flights": number | null,"n_weekly": number | null,"name": string | null,"position": number,"scan_id": number,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"enterprise_id": number,"n_airports"?: number | null,"n_flights"?: number | null,"n_weekly"?: number | null,"name"?: string | null,"position": number,"scan_id": number,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"enterprise_id"?: number,"n_airports"?: number | null,"n_flights"?: number | null,"n_weekly"?: number | null,"name"?: string | null,"position"?: number,"scan_id"?: number,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_scan_airlines_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_scan_airlines_scan_id_fkey"
      columns: ["scan_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "game_scan_airlines_scan_world_fkey"
      columns: ["scan_id","world_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id","world_id"]
    }
                  ]
                },"game_scan_airports": {
                  Row: {
                    "airport_code": string,"game_airport_id": number | null,"info": Json | null,"news": Json | null,"position": number,"scan_id": number,"stations": Json | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airport_code": string,"game_airport_id"?: number | null,"info"?: Json | null,"news"?: Json | null,"position": number,"scan_id": number,"stations"?: Json | null,"world_id": number
                  }
                  Update: {
                    "airport_code"?: string,"game_airport_id"?: number | null,"info"?: Json | null,"news"?: Json | null,"position"?: number,"scan_id"?: number,"stations"?: Json | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_scan_airports_scan_id_fkey"
      columns: ["scan_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "game_scan_airports_scan_world_fkey"
      columns: ["scan_id","world_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id","world_id"]
    }
                  ]
                },"game_scan_schedules": {
                  Row: {
                    "airline_id": number,"flights": NonNullable<Json>,"scan_id": number,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"flights"?: NonNullable<Json>,"scan_id": number,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"flights"?: NonNullable<Json>,"scan_id"?: number,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_scan_schedules_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_scan_schedules_scan_world_fkey"
      columns: ["scan_id","world_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id","world_id"]
    }
                  ]
                },"game_scans": {
                  Row: {
                    "id": number,"note": string | null,"status": string,"taken_at": string,"week": string | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: number,"note"?: string | null,"status"?: string,"taken_at"?: string,"week"?: string | null,"world_id": number
                  }
                  Update: {
                    "id"?: number,"note"?: string | null,"status"?: string,"taken_at"?: string,"week"?: string | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_scans_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_statement": {
                  Row: {
                    "airline": string,"airline_id": number,"amount": number,"blk": number | null,"captured_at": string | null,"descr": string,"flight_id": number | null,"occ": number,"pax": number | null,"route": string | null,"side": string,"ts": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline": string,"airline_id": number,"amount": number,"blk"?: number | null,"captured_at"?: string | null,"descr": string,"flight_id"?: number | null,"occ"?: number,"pax"?: number | null,"route"?: string | null,"side": string,"ts": string,"world_id": number
                  }
                  Update: {
                    "airline"?: string,"airline_id"?: number,"amount"?: number,"blk"?: number | null,"captured_at"?: string | null,"descr"?: string,"flight_id"?: number | null,"occ"?: number,"pax"?: number | null,"route"?: string | null,"side"?: string,"ts"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_statement_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_statement_flight_fkey"
      columns: ["flight_id","airline_id"]
isOneToOne: false
      referencedRelation: "game_flights"
      referencedColumns: ["id","airline_id"]
    },{
      foreignKeyName: "game_statement_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"groups": {
                  Row: {
                    "created_at": string,"id": number,"kind": string,"name": string,"note": string | null,"owner_user_id": string | null,"player_name": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: never,"kind": string,"name": string,"note"?: string | null,"owner_user_id"?: string | null,"player_name"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "created_at"?: string,"id"?: never,"kind"?: string,"name"?: string,"note"?: string | null,"owner_user_id"?: string | null,"player_name"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "groups_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"growth_log": {
                  Row: {
                    "airline_id": number,"created_at": string,"id": number,"logged_on": string,"move": string,"note": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"created_at"?: string,"id"?: never,"logged_on": string,"move": string,"note"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"created_at"?: string,"id"?: never,"logged_on"?: string,"move"?: string,"note"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "growth_log_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "growth_log_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"ingest_secret": {
                  Row: {
                    "secret": string
                  }
                  ComputedFields: never
                  Insert: {
                    "secret": string
                  }
                  Update: {
                    "secret"?: string
                  }
                  Relationships: [
                    
                  ]
                },"interline_agreements": {
                  Row: {
                    "airline_id": number,"country_code": string,"created_at": string,"decided_on": string | null,"id": number,"note": string | null,"partner": string | null,"partner_airline_id": number | null,"status": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"country_code": string,"created_at"?: string,"decided_on"?: string | null,"id"?: never,"note"?: string | null,"partner"?: string | null,"partner_airline_id"?: number | null,"status"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"country_code"?: string,"created_at"?: string,"decided_on"?: string | null,"id"?: never,"note"?: string | null,"partner"?: string | null,"partner_airline_id"?: number | null,"status"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "interline_agreements_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "interline_agreements_country_code_fkey"
      columns: ["country_code"]
isOneToOne: false
      referencedRelation: "countries"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "interline_agreements_partner_fkey"
      columns: ["partner_airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "interline_agreements_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"job_runs": {
                  Row: {
                    "details": Json | null,"finished_at": string | null,"for_day": string | null,"for_month": string | null,"id": number,"job": string,"note": string | null,"started_at": string,"status": string,"world_id": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "details"?: Json | null,"finished_at"?: string | null,"for_day"?: string | null,"for_month"?: string | null,"id"?: never,"job": string,"note"?: string | null,"started_at"?: string,"status"?: string,"world_id"?: number | null
                  }
                  Update: {
                    "details"?: Json | null,"finished_at"?: string | null,"for_day"?: string | null,"for_month"?: string | null,"id"?: never,"job"?: string,"note"?: string | null,"started_at"?: string,"status"?: string,"world_id"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "job_runs_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"load_days": {
                  Row: {
                    "created_at": string,"done": boolean,"entered_at": string | null,"game_date": string,"saved_at_ms": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"done"?: boolean,"entered_at"?: string | null,"game_date": string,"saved_at_ms"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "created_at"?: string,"done"?: boolean,"entered_at"?: string | null,"game_date"?: string,"saved_at_ms"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "load_days_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"load_entries": {
                  Row: {
                    "airline_id": number,"created_at": string,"eco_pct": number | null,"entered_at": string | null,"flight_no": number,"game_date": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"created_at"?: string,"eco_pct"?: number | null,"entered_at"?: string | null,"flight_no": number,"game_date": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"created_at"?: string,"eco_pct"?: number | null,"entered_at"?: string | null,"flight_no"?: number,"game_date"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "load_entries_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "load_entries_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"markets": {
                  Row: {
                    "airline_id": number,"created_at": string,"id": number,"layout": string,"name": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"created_at"?: string,"id"?: never,"layout": string,"name": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"created_at"?: string,"id"?: never,"layout"?: string,"name"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "markets_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "markets_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"monthly_checks": {
                  Row: {
                    "airline_id": number | null,"created_at": string,"id": number,"last_done_on": string | null,"task": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id"?: number | null,"created_at"?: string,"id"?: never,"last_done_on"?: string | null,"task": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number | null,"created_at"?: string,"id"?: never,"last_done_on"?: string | null,"task"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "monthly_checks_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "monthly_checks_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"plan_card_legs": {
                  Row: {
                    "block_min": number | null,"created_at": string,"days_utc": (number)[],"dep_utc_min": number | null,"dest_code": string | null,"flight_no": number | null,"id": number,"origin_code": string | null,"plan_card_id": number,"position": number,"service_code": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "block_min"?: number | null,"created_at"?: string,"days_utc"?: (number)[],"dep_utc_min"?: number | null,"dest_code"?: string | null,"flight_no"?: number | null,"id"?: never,"origin_code"?: string | null,"plan_card_id": number,"position": number,"service_code"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "block_min"?: number | null,"created_at"?: string,"days_utc"?: (number)[],"dep_utc_min"?: number | null,"dest_code"?: string | null,"flight_no"?: number | null,"id"?: never,"origin_code"?: string | null,"plan_card_id"?: number,"position"?: number,"service_code"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "plan_card_legs_card_fkey"
      columns: ["plan_card_id","world_id"]
isOneToOne: false
      referencedRelation: "plan_cards"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "plan_card_legs_dest_code_fkey"
      columns: ["dest_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "plan_card_legs_origin_code_fkey"
      columns: ["origin_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "plan_card_legs_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"plan_cards": {
                  Row: {
                    "aircraft_id": number,"airline_id": number,"base_code": string | null,"config_id": number | null,"created_at": string,"extra": NonNullable<Json>,"id": number,"note": string | null,"title": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": number,"airline_id": number,"base_code"?: string | null,"config_id"?: number | null,"created_at"?: string,"extra"?: NonNullable<Json>,"id"?: never,"note"?: string | null,"title"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_id"?: number,"airline_id"?: number,"base_code"?: string | null,"config_id"?: number | null,"created_at"?: string,"extra"?: NonNullable<Json>,"id"?: never,"note"?: string | null,"title"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "plan_cards_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "plan_cards_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "plan_cards_base_code_fkey"
      columns: ["base_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "plan_cards_config_fkey"
      columns: ["config_id","world_id"]
isOneToOne: false
      referencedRelation: "cabin_configs"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "plan_cards_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"planner_scripts": {
                  Row: {
                    "content": string,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "content": string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "content"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"planner_users": {
                  Row: {
                    "email": string
                  }
                  ComputedFields: never
                  Insert: {
                    "email": string
                  }
                  Update: {
                    "email"?: string
                  }
                  Relationships: [
                    
                  ]
                },"report_access": {
                  Row: {
                    "pass_hash": string
                  }
                  ComputedFields: never
                  Insert: {
                    "pass_hash": string
                  }
                  Update: {
                    "pass_hash"?: string
                  }
                  Relationships: [
                    
                  ]
                },"rotations": {
                  Row: {
                    "airline_id": number,"created_at": string,"extra": NonNullable<Json>,"fare_pct": number | null,"id": number,"launched_on": string | null,"legacy_key": string | null,"note": string | null,"route_id": number,"service_code": string | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"created_at"?: string,"extra"?: NonNullable<Json>,"fare_pct"?: number | null,"id"?: never,"launched_on"?: string | null,"legacy_key"?: string | null,"note"?: string | null,"route_id": number,"service_code"?: string | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"created_at"?: string,"extra"?: NonNullable<Json>,"fare_pct"?: number | null,"id"?: never,"launched_on"?: string | null,"legacy_key"?: string | null,"note"?: string | null,"route_id"?: number,"service_code"?: string | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "rotations_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "rotations_route_fkey"
      columns: ["route_id","world_id"]
isOneToOne: false
      referencedRelation: "routes"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "rotations_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"route_days": {
                  Row: {
                    "airline_id": number,"costs": number | null,"day": string,"dest_code": string,"eco_fare_avg": number | null,"flights": number,"origin_code": string,"passengers": number | null,"profit": number | null,"revenue": number | null,"route_id": number | null,"seats": number | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"costs"?: number | null,"day": string,"dest_code": string,"eco_fare_avg"?: number | null,"flights": number,"origin_code": string,"passengers"?: number | null,"profit"?: number | null,"revenue"?: number | null,"route_id"?: number | null,"seats"?: number | null,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"costs"?: number | null,"day"?: string,"dest_code"?: string,"eco_fare_avg"?: number | null,"flights"?: number,"origin_code"?: string,"passengers"?: number | null,"profit"?: number | null,"revenue"?: number | null,"route_id"?: number | null,"seats"?: number | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "route_days_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "route_days_route_fkey"
      columns: ["route_id","world_id"]
isOneToOne: false
      referencedRelation: "routes"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "route_days_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"routes": {
                  Row: {
                    "airline_id": number,"cabin_choice": string | null,"city": string | null,"city_override": string | null,"country_label": string | null,"created_at": string,"dest_code": string,"distance_km": number | null,"distance_override_km": number | null,"edit_kept": boolean,"hub_code": string,"id": number,"market_cleared": boolean,"market_id": number | null,"market_override_id": number | null,"removed": boolean,"removed_note": string | null,"source": string,"stars": number | null,"stars_override": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"cabin_choice"?: string | null,"city"?: string | null,"city_override"?: string | null,"country_label"?: string | null,"created_at"?: string,"dest_code": string,"distance_km"?: number | null,"distance_override_km"?: number | null,"edit_kept"?: boolean,"hub_code": string,"id"?: never,"market_cleared"?: boolean,"market_id"?: number | null,"market_override_id"?: number | null,"removed"?: boolean,"removed_note"?: string | null,"source": string,"stars"?: number | null,"stars_override"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"cabin_choice"?: string | null,"city"?: string | null,"city_override"?: string | null,"country_label"?: string | null,"created_at"?: string,"dest_code"?: string,"distance_km"?: number | null,"distance_override_km"?: number | null,"edit_kept"?: boolean,"hub_code"?: string,"id"?: never,"market_cleared"?: boolean,"market_id"?: number | null,"market_override_id"?: number | null,"removed"?: boolean,"removed_note"?: string | null,"source"?: string,"stars"?: number | null,"stars_override"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "routes_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "routes_dest_code_fkey"
      columns: ["dest_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "routes_hub_code_fkey"
      columns: ["hub_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "routes_market_fkey"
      columns: ["market_id","world_id"]
isOneToOne: false
      referencedRelation: "markets"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "routes_market_override_fkey"
      columns: ["market_override_id","world_id"]
isOneToOne: false
      referencedRelation: "markets"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "routes_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"scan_airline_airports": {
                  Row: {
                    "airline_id": number,"airport_code": string,"destinations": number,"scan_id": number,"weekly_departures": number,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"airport_code": string,"destinations": number,"scan_id": number,"weekly_departures": number,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"airport_code"?: string,"destinations"?: number,"scan_id"?: number,"weekly_departures"?: number,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "scan_airline_airports_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "scan_airline_airports_scan_world_fkey"
      columns: ["scan_id","world_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id","world_id"]
    }
                  ]
                },"scan_airline_markets": {
                  Row: {
                    "airline_id": number,"city_pairs": number,"market": string,"scan_id": number,"weekly_departures": number,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id": number,"city_pairs": number,"market": string,"scan_id": number,"weekly_departures": number,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number,"city_pairs"?: number,"market"?: string,"scan_id"?: number,"weekly_departures"?: number,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "scan_airline_markets_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "scan_airline_markets_scan_world_fkey"
      columns: ["scan_id","world_id"]
isOneToOne: false
      referencedRelation: "game_scans"
      referencedColumns: ["id","world_id"]
    }
                  ]
                },"service_profiles": {
                  Row: {
                    "airline_id": number | null,"code": string,"created_at": string,"id": number,"note": string | null,"up_to_km": number | null,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id"?: number | null,"code": string,"created_at"?: string,"id"?: never,"note"?: string | null,"up_to_km"?: number | null,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number | null,"code"?: string,"created_at"?: string,"id"?: never,"note"?: string | null,"up_to_km"?: number | null,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "service_profiles_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "service_profiles_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"settings": {
                  Row: {
                    "airline_id": number | null,"created_at": string,"description": string | null,"id": number,"key": string,"reason": string | null,"since": string | null,"unit": string | null,"updated_at": string,"value": NonNullable<Json>,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id"?: number | null,"created_at"?: string,"description"?: string | null,"id"?: never,"key": string,"reason"?: string | null,"since"?: string | null,"unit"?: string | null,"updated_at"?: string,"value": NonNullable<Json>,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number | null,"created_at"?: string,"description"?: string | null,"id"?: never,"key"?: string,"reason"?: string | null,"since"?: string | null,"unit"?: string | null,"updated_at"?: string,"value"?: NonNullable<Json>,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "settings_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "settings_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"site_content": {
                  Row: {
                    "key": string,"updated_at": string,"value": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "key": string,"updated_at"?: string,"value": NonNullable<Json>
                  }
                  Update: {
                    "key"?: string,"updated_at"?: string,"value"?: NonNullable<Json>
                  }
                  Relationships: [
                    
                  ]
                },"site_posts": {
                  Row: {
                    "airline": string | null,"auto": boolean,"body": string | null,"id": number,"image": string | null,"image_credit": string | null,"published_at": string,"slug": string | null,"summary": string | null,"tag": string | null,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "airline"?: string | null,"auto"?: boolean,"body"?: string | null,"id"?: number,"image"?: string | null,"image_credit"?: string | null,"published_at"?: string,"slug"?: string | null,"summary"?: string | null,"tag"?: string | null,"title": string
                  }
                  Update: {
                    "airline"?: string | null,"auto"?: boolean,"body"?: string | null,"id"?: number,"image"?: string | null,"image_credit"?: string | null,"published_at"?: string,"slug"?: string | null,"summary"?: string | null,"tag"?: string | null,"title"?: string
                  }
                  Relationships: [
                    
                  ]
                },"site_reports": {
                  Row: {
                    "id": number,"kind": string,"pdf_b64": string | null,"period": string,"published_at": string | null,"status": string,"summary": string | null,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: number,"kind": string,"pdf_b64"?: string | null,"period": string,"published_at"?: string | null,"status"?: string,"summary"?: string | null,"title": string
                  }
                  Update: {
                    "id"?: number,"kind"?: string,"pdf_b64"?: string | null,"period"?: string,"published_at"?: string | null,"status"?: string,"summary"?: string | null,"title"?: string
                  }
                  Relationships: [
                    
                  ]
                },"spending_log": {
                  Row: {
                    "aircraft_id": number | null,"airline_id": number,"amount": number,"created_at": string,"id": number,"kind": string,"note": string | null,"spent_on": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id"?: number | null,"airline_id": number,"amount": number,"created_at"?: string,"id"?: never,"kind": string,"note"?: string | null,"spent_on": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "aircraft_id"?: number | null,"airline_id"?: number,"amount"?: number,"created_at"?: string,"id"?: never,"kind"?: string,"note"?: string | null,"spent_on"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "spending_log_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "spending_log_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "spending_log_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"todo_items": {
                  Row: {
                    "body": string,"created_at": string,"id": number,"position": number,"todo_id": number,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "body": string,"created_at"?: string,"id"?: never,"position": number,"todo_id": number,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "body"?: string,"created_at"?: string,"id"?: never,"position"?: number,"todo_id"?: number,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "todo_items_todo_fkey"
      columns: ["todo_id","world_id"]
isOneToOne: false
      referencedRelation: "todos"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "todo_items_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"todos": {
                  Row: {
                    "airline_id": number | null,"created_at": string,"done": boolean,"done_at": string | null,"due_on": string | null,"extra": NonNullable<Json>,"id": number,"legacy_key": string | null,"note": string | null,"title": string,"updated_at": string,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airline_id"?: number | null,"created_at"?: string,"done"?: boolean,"done_at"?: string | null,"due_on"?: string | null,"extra"?: NonNullable<Json>,"id"?: never,"legacy_key"?: string | null,"note"?: string | null,"title": string,"updated_at"?: string,"world_id": number
                  }
                  Update: {
                    "airline_id"?: number | null,"created_at"?: string,"done"?: boolean,"done_at"?: string | null,"due_on"?: string | null,"extra"?: NonNullable<Json>,"id"?: never,"legacy_key"?: string | null,"note"?: string | null,"title"?: string,"updated_at"?: string,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "todos_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "todos_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"world_airports": {
                  Row: {
                    "airport_code": string,"closed": boolean,"created_at": string,"game_airport_id": number | null,"mct_min": number | null,"night_ban_from": string | null,"night_ban_to": string | null,"note": string | null,"updated_at": string,"utc_offset_override": number | null,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "airport_code": string,"closed"?: boolean,"created_at"?: string,"game_airport_id"?: number | null,"mct_min"?: number | null,"night_ban_from"?: string | null,"night_ban_to"?: string | null,"note"?: string | null,"updated_at"?: string,"utc_offset_override"?: number | null,"world_id": number
                  }
                  Update: {
                    "airport_code"?: string,"closed"?: boolean,"created_at"?: string,"game_airport_id"?: number | null,"mct_min"?: number | null,"night_ban_from"?: string | null,"night_ban_to"?: string | null,"note"?: string | null,"updated_at"?: string,"utc_offset_override"?: number | null,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "world_airports_airport_code_fkey"
      columns: ["airport_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "world_airports_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"world_rules": {
                  Row: {
                    "created_at": string,"description": string | null,"id": number,"key": string,"kind": string,"since": string | null,"source": string | null,"unit": string | null,"updated_at": string,"value": NonNullable<Json>,"world_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"description"?: string | null,"id"?: never,"key": string,"kind": string,"since"?: string | null,"source"?: string | null,"unit"?: string | null,"updated_at"?: string,"value": NonNullable<Json>,"world_id": number
                  }
                  Update: {
                    "created_at"?: string,"description"?: string | null,"id"?: never,"key"?: string,"kind"?: string,"since"?: string | null,"source"?: string | null,"unit"?: string | null,"updated_at"?: string,"value"?: NonNullable<Json>,"world_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "world_rules_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"worlds": {
                  Row: {
                    "created_at": string,"ended_on": string | null,"game_host": string,"id": number,"is_default": boolean,"kind": string,"name": string,"note": string | null,"started_on": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"ended_on"?: string | null,"game_host": string,"id"?: never,"is_default"?: boolean,"kind": string,"name": string,"note"?: string | null,"started_on"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"ended_on"?: string | null,"game_host"?: string,"id"?: never,"is_default"?: boolean,"kind"?: string,"name"?: string,"note"?: string | null,"started_on"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            "backup_runs": {
                  Row: {
                    "bytes": number | null,"commit_sha": string | null,"files": number | null,"id": number | null,"kind": string | null,"note": string | null,"object_key": string | null,"ok": boolean | null,"ran_at": string | null,"rows": number | null,"tables": number | null
                  }
                  ComputedFields: never
                  Insert: {
                           "bytes"?: number | null,"commit_sha"?: string | null,"files"?: number | null,"id"?: number | null,"kind"?: string | null,"note"?: string | null,"object_key"?: string | null,"ok"?: boolean | null,"ran_at"?: string | null,"rows"?: number | null,"tables"?: number | null
                         }
                        Update: {
                           "bytes"?: number | null,"commit_sha"?: string | null,"files"?: number | null,"id"?: number | null,"kind"?: string | null,"note"?: string | null,"object_key"?: string | null,"ok"?: boolean | null,"ran_at"?: string | null,"rows"?: number | null,"tables"?: number | null
                         }
                        Relationships: [
                    
                  ]
                },"capture_cash": {
                  Row: {
                    "airline_id": number | null,"cash": number | null,"cash_at": string | null,"day": string | null,"fixed_next7": number | null,"world_id": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "game_balance_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "game_balance_world_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"flight_legs_local": {
                  Row: {
                    "aircraft_id": number | null,"airline_id": number | null,"arr_local": string | null,"arr_local_day_offset": number | null,"arr_local_min": number | null,"arr_utc_day_offset": number | null,"arr_utc_min": number | null,"block_min": number | null,"days_local": (number)[] | null,"days_utc": (number)[] | null,"dep_local": string | null,"dep_local_min": number | null,"dep_utc_min": number | null,"dest_code": string | null,"flight_code": string | null,"flight_no": number | null,"id": number | null,"leg_no": number | null,"origin_code": string | null,"rotation_id": number | null,"world_id": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "flight_legs_aircraft_fkey"
      columns: ["aircraft_id","world_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "flight_legs_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "flight_legs_dest_code_fkey"
      columns: ["dest_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "flight_legs_origin_code_fkey"
      columns: ["origin_code"]
isOneToOne: false
      referencedRelation: "airports"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "flight_legs_rotation_fkey"
      columns: ["rotation_id","airline_id"]
isOneToOne: false
      referencedRelation: "rotations"
      referencedColumns: ["id","airline_id"]
    },{
      foreignKeyName: "flight_legs_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"flight_no_clashes": {
                  Row: {
                    "aircraft_ids": (number)[] | null,"airline_id": number | null,"flight_code": string | null,"flight_no": number | null,"leg_ids": (number)[] | null,"legs": number | null,"weekday": number | null,"world_id": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "flight_legs_airline_fkey"
      columns: ["airline_id","world_id"]
isOneToOne: false
      referencedRelation: "airlines"
      referencedColumns: ["id","world_id"]
    },{
      foreignKeyName: "flight_legs_world_id_fkey"
      columns: ["world_id"]
isOneToOne: false
      referencedRelation: "worlds"
      referencedColumns: ["id"]
    }
                  ]
                },"game_flight_pnl": {
                  Row: {
                    "airline": string | null,"atc": number | null,"blk": number | null,"cargo_income": number | null,"fuel": number | null,"handling": number | null,"landing": number | null,"maintenance": number | null,"onboard": number | null,"pax": number | null,"pax_income": number | null,"profit": number | null,"route": string | null,"routes_n": number | null,"tail": string | null,"ts": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    
                  ]
                },"game_loads": {
                  Row: {
                    "airline": string | null,"arr_time": string | null,"bus": number | null,"bus_fare": number | null,"bus_pax": number | null,"bus_seats": number | null,"captured_at": string | null,"cargo": number | null,"cargo_cap": number | null,"cargo_rate": number | null,"cargo_units": number | null,"code": string | null,"dep_time": string | null,"dest": string | null,"eco": number | null,"eco_fare": number | null,"eco_pax": number | null,"eco_seats": number | null,"flight_date": string | null,"fst": number | null,"fst_fare": number | null,"fst_pax": number | null,"fst_seats": number | null,"origin": string | null,"status": string | null,"tail": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    
                  ]
                },"game_ops_recent": {
                  Row: {
                    "airline": string | null,"costs": number | null,"flights": number | null,"hours": number | null,"income": number | null,"last_ts": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    
                  ]
                }
          }
          Functions: {
            "aircraft_profit":
{ Args: { "p_airline_id": number,"p_as_of"?: string,"p_days"?: number }; Returns: Json
                           },
"airline_cards":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           },
"airline_profit":
{ Args: { "p_airline_id": number,"p_as_of"?: string }; Returns: Json
                           },
"as_num":
{ Args: { "p": string }; Returns: number
                           },
"capture_airlines":
{ Args: { "p_key": string }; Returns: Json
                           },
"capture_fare_actions":
{ Args: { "p_key": string }; Returns: Json
                           },
"capture_ingest":
{ Args: { "p_airline": string,"p_key": string,"p_kind": string,"p_page": string,"p_rows": Json }; Returns: Json
                           },
"capture_scan":
{ Args: { "p_key": string,"p_kind": string,"p_payload": Json }; Returns: Json
                           },
"capture_status":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           },
"cash_forecast":
{ Args: { "p_airline_id": number,"p_as_of"?: string,"p_orders"?: Json }; Returns: Json
                           },
"cash_log":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           },
"export_capture":
{ Args: { "p_days"?: number,"p_secret": string }; Returns: Json
                           },
"export_for_report":
{ Args: { "p_arg"?: string,"p_kind": string,"p_secret": string }; Returns: Json
                           },
"export_repo_bootstrap":
{ Args: { "p_secret": string }; Returns: Json
                           },
"fare_changes":
{ Args: { "p_airline_id": number,"p_as_of"?: string }; Returns: Json
                           },
"fare_ladder":
{ Args: { "p_airline_id": number,"p_as_of"?: string }; Returns: Json
                           },
"fare_plan_status":
{ Args: { "p_airline_id": number,"p_as_of"?: string }; Returns: Json
                           },
"growth_signals":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           },
"hub_progress":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           },
"ingest_snapshot":
{ Args: { "p_kind": string,"p_payload": Json,"p_secret": string }; Returns: Json
                           },
"is_planner_user":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"loads_by_day":
{ Args: { "p_from": string,"p_to": string,"p_world_id": number }; Returns: Json
                           },
"order_cabin":
{ Args: { "p_airline_id": number,"p_type_id": number }; Returns: Json
                           },
"parse_capture":
{ Args: { "p_id": number }; Returns: Json
                           },
"planner_data_set":
{ Args: { "p_key": string,"p_secret": string,"p_value": Json }; Returns: Json
                           },
"planner_save":
{ Args: { "p_changes": Json,"p_client": string }; Returns: Json
                           },
"route_loads":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           },
"route_profit":
{ Args: { "p_airline_id": number,"p_as_of"?: string,"p_days"?: number }; Returns: Json
                           },
"rules_input":
{ Args: { "p_routes"?: string,"p_world_id"?: number }; Returns: Json
                           },
"save_script":
{ Args: { "p_content": string,"p_name": string,"p_secret": string }; Returns: Json
                           },
"site_admin":
{ Args: { "p_kind": string,"p_payload": Json,"p_secret": string }; Returns: Json
                           },
"site_investor":
{ Args: { "p_password": string }; Returns: Json
                           },
"site_newsletter":
{ Args: { "p_id": number }; Returns: Json
                           },
"site_public":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"site_remove_airline_logo":
{ Args: { "p_airline": string }; Returns: Json
                           },
"site_remove_airport_photo":
{ Args: { "p_code": string }; Returns: Json
                           },
"site_report":
{ Args: { "p_id": number,"p_password": string }; Returns: Json
                           },
"site_set_airline_logo":
{ Args: { "p_airline": string,"p_path"?: string,"p_url": string }; Returns: Json
                           },
"site_set_airport_photo":
{ Args: { "p_code": string,"p_credit"?: string,"p_path"?: string,"p_url": string }; Returns: Json
                           },
"system_status":
{ Args: { "p_as_of"?: string,"p_world_id"?: number }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            
          }
        }
} as const
