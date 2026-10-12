export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      airlines: {
        Row: {
          active: boolean
          blurb: string | null
          country_code: string | null
          created_at: string
          founded_on: string | null
          game_id: number
          game_name: string | null
          group_id: number | null
          home_airport_code: string | null
          iata_code: string | null
          id: number
          is_lcc: boolean
          livery_color: string | null
          low_demand: boolean
          photo_city: string | null
          planner_name: string | null
          position: number | null
          public_name: string | null
          region_text: string | null
          role_text: string | null
          slug: string | null
          updated_at: string
          world_id: number
        }
        Insert: { [column: string]: Json | undefined }
        Update: { [column: string]: Json | undefined }
        Relationships: []
      }
      change_log: {
        Row: {
          actor: string | null
          actor_detail: string | null
          changed_at: string
          db_role: string | null
          id: number
          new_values: Json | null
          old_values: Json | null
          op: string
          row_key: Json
          table_name: string
          txid: number | null
          world_id: number | null
        }
        Insert: { [column: string]: Json | undefined }
        Update: { [column: string]: Json | undefined }
        Relationships: []
      }
      groups: {
        Row: {
          created_at: string
          id: number
          kind: string
          name: string
          note: string | null
          owner_user_id: string | null
          player_name: string | null
          updated_at: string
          world_id: number
        }
        Insert: { [column: string]: Json | undefined }
        Update: { [column: string]: Json | undefined }
        Relationships: []
      }
      settings: {
        Row: {
          airline_id: number | null
          created_at: string
          description: string | null
          id: number
          key: string
          reason: string | null
          since: string | null
          unit: string | null
          updated_at: string
          value: Json
          world_id: number
        }
        Insert: { [column: string]: Json | undefined }
        Update: { [column: string]: Json | undefined }
        Relationships: []
      }
      worlds: {
        Row: {
          created_at: string
          ended_on: string | null
          game_host: string
          id: number
          is_default: boolean
          kind: string
          name: string
          note: string | null
          started_on: string | null
          updated_at: string
        }
        Insert: { [column: string]: Json | undefined }
        Update: { [column: string]: Json | undefined }
        Relationships: []
      }
      aircraft: Generic
      aircraft_cabin_keeps: Generic
      aircraft_types: Generic
      airline_aircraft_types: Generic
      airline_bases: Generic
      airports: Generic
      cabin_configs: Generic
      cash_entries: Generic
      countries: Generic
      dismissals: Generic
      fare_plan: Generic
      flight_legs: Generic
      growth_log: Generic
      interline_agreements: Generic
      load_days: Generic
      load_entries: Generic
      markets: Generic
      monthly_checks: Generic
      plan_card_legs: Generic
      plan_cards: Generic
      rotations: Generic
      routes: Generic
      service_profiles: Generic
      spending_log: Generic
      todo_items: Generic
      todos: Generic
      world_airports: Generic
      world_rules: Generic
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      is_planner_user: { Args: never; Returns: boolean }
      planner_save: { Args: { p_changes: Json; p_client: string }; Returns: Json }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type Generic = {
  Row: { [column: string]: Json }
  Insert: { [column: string]: Json | undefined }
  Update: { [column: string]: Json | undefined }
  Relationships: []
}

export type Tables<T extends keyof Database["public"]["Tables"]> = Database["public"]["Tables"][T]["Row"]
