export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      data_source_runs: {
        Row: {
          error_message: string | null
          finished_at: string | null
          id: string
          indicator_id: string | null
          rows_affected: number | null
          source: string
          started_at: string
          status: Database["public"]["Enums"]["run_status"]
        }
        Insert: {
          error_message?: string | null
          finished_at?: string | null
          id?: string
          indicator_id?: string | null
          rows_affected?: number | null
          source: string
          started_at?: string
          status: Database["public"]["Enums"]["run_status"]
        }
        Update: {
          error_message?: string | null
          finished_at?: string | null
          id?: string
          indicator_id?: string | null
          rows_affected?: number | null
          source?: string
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
        }
        Relationships: [
          {
            foreignKeyName: "data_source_runs_indicator_id_fkey"
            columns: ["indicator_id"]
            isOneToOne: false
            referencedRelation: "indicators"
            referencedColumns: ["id"]
          },
        ]
      }
      documents: {
        Row: {
          created_at: string
          doc_type: string | null
          id: string
          indicator_id: string | null
          storage_path: string
          title: string
          uploaded_by: string | null
          visibility: Database["public"]["Enums"]["visibility_level"]
        }
        Insert: {
          created_at?: string
          doc_type?: string | null
          id?: string
          indicator_id?: string | null
          storage_path: string
          title: string
          uploaded_by?: string | null
          visibility?: Database["public"]["Enums"]["visibility_level"]
        }
        Update: {
          created_at?: string
          doc_type?: string | null
          id?: string
          indicator_id?: string | null
          storage_path?: string
          title?: string
          uploaded_by?: string | null
          visibility?: Database["public"]["Enums"]["visibility_level"]
        }
        Relationships: [
          {
            foreignKeyName: "documents_indicator_id_fkey"
            columns: ["indicator_id"]
            isOneToOne: false
            referencedRelation: "indicators"
            referencedColumns: ["id"]
          },
        ]
      }
      geographies: {
        Row: {
          code: string
          level: Database["public"]["Enums"]["geo_level"]
          name: string
          parent_code: string | null
        }
        Insert: {
          code: string
          level: Database["public"]["Enums"]["geo_level"]
          name: string
          parent_code?: string | null
        }
        Update: {
          code?: string
          level?: Database["public"]["Enums"]["geo_level"]
          name?: string
          parent_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "geographies_parent_code_fkey"
            columns: ["parent_code"]
            isOneToOne: false
            referencedRelation: "geographies"
            referencedColumns: ["code"]
          },
        ]
      }
      indicator_metadata: {
        Row: {
          hamtad_datum: string | null
          indicator_id: string
          kalla: string
          kalla_uppdaterad_datum: string | null
          note: string | null
          period: string | null
          styrande_kalla: string
          tillganglighetsdatum: string | null
          updated_at: string
        }
        Insert: {
          hamtad_datum?: string | null
          indicator_id: string
          kalla: string
          kalla_uppdaterad_datum?: string | null
          note?: string | null
          period?: string | null
          styrande_kalla: string
          tillganglighetsdatum?: string | null
          updated_at?: string
        }
        Update: {
          hamtad_datum?: string | null
          indicator_id?: string
          kalla?: string
          kalla_uppdaterad_datum?: string | null
          note?: string | null
          period?: string | null
          styrande_kalla?: string
          tillganglighetsdatum?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "indicator_metadata_indicator_id_fkey"
            columns: ["indicator_id"]
            isOneToOne: true
            referencedRelation: "indicators"
            referencedColumns: ["id"]
          },
        ]
      }
      indicators: {
        Row: {
          created_at: string
          description: string
          frequency: string | null
          id: string
          is_example: boolean
          name: string
          source_table_id: string | null
          styrande_kalla: string
          unit: string
          visibility: Database["public"]["Enums"]["visibility_level"]
        }
        Insert: {
          created_at?: string
          description?: string
          frequency?: string | null
          id: string
          is_example?: boolean
          name: string
          source_table_id?: string | null
          styrande_kalla: string
          unit?: string
          visibility?: Database["public"]["Enums"]["visibility_level"]
        }
        Update: {
          created_at?: string
          description?: string
          frequency?: string | null
          id?: string
          is_example?: boolean
          name?: string
          source_table_id?: string | null
          styrande_kalla?: string
          unit?: string
          visibility?: Database["public"]["Enums"]["visibility_level"]
        }
        Relationships: []
      }
      observations: {
        Row: {
          dimensions: Json
          geo_code: string
          id: string
          indicator_id: string
          period: string
          value: number | null
        }
        Insert: {
          dimensions?: Json
          geo_code: string
          id?: string
          indicator_id: string
          period: string
          value?: number | null
        }
        Update: {
          dimensions?: Json
          geo_code?: string
          id?: string
          indicator_id?: string
          period?: string
          value?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "observations_geo_code_fkey"
            columns: ["geo_code"]
            isOneToOne: false
            referencedRelation: "geographies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "observations_indicator_id_fkey"
            columns: ["indicator_id"]
            isOneToOne: false
            referencedRelation: "indicators"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      publish_indicator: {
        Args: {
          p_indicator_id: string
          p_kalla_uppdaterad_datum?: string
          p_observations: Json
          p_rows_affected?: number
        }
        Returns: Json
      }
    }
    Enums: {
      app_role: "admin" | "editor" | "registered"
      geo_level: "riket" | "län" | "kommun"
      run_status: "started" | "no_change" | "succeeded" | "failed"
      visibility_level: "publik" | "inloggad" | "admin"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "editor", "registered"],
      geo_level: ["riket", "län", "kommun"],
      run_status: ["started", "no_change", "succeeded", "failed"],
      visibility_level: ["publik", "inloggad", "admin"],
    },
  },
} as const
