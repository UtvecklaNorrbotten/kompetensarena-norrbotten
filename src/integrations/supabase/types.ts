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
          details: Json | null
          error_message: string | null
          finished_at: string | null
          id: string
          indicator_id: string | null
          rows_affected: number | null
          source: string
          source_id: string | null
          source_period: string | null
          started_at: string
          status: Database["public"]["Enums"]["run_status"]
        }
        Insert: {
          details?: Json | null
          error_message?: string | null
          finished_at?: string | null
          id?: string
          indicator_id?: string | null
          rows_affected?: number | null
          source: string
          source_id?: string | null
          source_period?: string | null
          started_at?: string
          status: Database["public"]["Enums"]["run_status"]
        }
        Update: {
          details?: Json | null
          error_message?: string | null
          finished_at?: string | null
          id?: string
          indicator_id?: string | null
          rows_affected?: number | null
          source?: string
          source_id?: string | null
          source_period?: string | null
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
          {
            foreignKeyName: "data_source_runs_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "data_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      data_source_state: {
        Row: {
          details: Json
          last_checked_at: string | null
          last_error: string | null
          last_status: string
          last_successful_at: string | null
          latest_available_period: string | null
          latest_successful_period: string | null
          source_id: string
          updated_at: string
        }
        Insert: {
          details?: Json
          last_checked_at?: string | null
          last_error?: string | null
          last_status?: string
          last_successful_at?: string | null
          latest_available_period?: string | null
          latest_successful_period?: string | null
          source_id: string
          updated_at?: string
        }
        Update: {
          details?: Json
          last_checked_at?: string | null
          last_error?: string | null
          last_status?: string
          last_successful_at?: string | null
          latest_available_period?: string | null
          latest_successful_period?: string | null
          source_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "data_source_state_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: true
            referencedRelation: "data_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      data_sources: {
        Row: {
          active: boolean
          cadence: string | null
          check_from_day_of_month: number | null
          created_at: string
          id: string
          name: string
          provider: string
          source_url: string | null
        }
        Insert: {
          active?: boolean
          cadence?: string | null
          check_from_day_of_month?: number | null
          created_at?: string
          id: string
          name: string
          provider: string
          source_url?: string | null
        }
        Update: {
          active?: boolean
          cadence?: string | null
          check_from_day_of_month?: number | null
          created_at?: string
          id?: string
          name?: string
          provider?: string
          source_url?: string | null
        }
        Relationships: []
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
      etl_batch_chunks: {
        Row: {
          batch_id: string
          checksum: string
          chunk_index: number
          created_at: string
          row_count: number
        }
        Insert: {
          batch_id: string
          checksum: string
          chunk_index: number
          created_at?: string
          row_count: number
        }
        Update: {
          batch_id?: string
          checksum?: string
          chunk_index?: number
          created_at?: string
          row_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "etl_batch_chunks_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "etl_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      etl_batches: {
        Row: {
          base_batch_id: string | null
          created_at: string
          error_message: string | null
          expected_chunks: number
          expected_rows: number | null
          id: string
          indicator_id: string
          kalla_uppdaterad_datum: string | null
          last_activity_at: string
          received_chunks: number
          received_rows: number
          replace_period: string | null
          run_id: string | null
          source: string
          status: Database["public"]["Enums"]["etl_batch_status"]
        }
        Insert: {
          base_batch_id?: string | null
          created_at?: string
          error_message?: string | null
          expected_chunks: number
          expected_rows?: number | null
          id?: string
          indicator_id: string
          kalla_uppdaterad_datum?: string | null
          last_activity_at?: string
          received_chunks?: number
          received_rows?: number
          replace_period?: string | null
          run_id?: string | null
          source: string
          status?: Database["public"]["Enums"]["etl_batch_status"]
        }
        Update: {
          base_batch_id?: string | null
          created_at?: string
          error_message?: string | null
          expected_chunks?: number
          expected_rows?: number | null
          id?: string
          indicator_id?: string
          kalla_uppdaterad_datum?: string | null
          last_activity_at?: string
          received_chunks?: number
          received_rows?: number
          replace_period?: string | null
          run_id?: string | null
          source?: string
          status?: Database["public"]["Enums"]["etl_batch_status"]
        }
        Relationships: [
          {
            foreignKeyName: "etl_batches_base_batch_id_fkey"
            columns: ["base_batch_id"]
            isOneToOne: false
            referencedRelation: "etl_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "etl_batches_indicator_id_fkey"
            columns: ["indicator_id"]
            isOneToOne: false
            referencedRelation: "indicators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "etl_batches_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "data_source_runs"
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
      indicator_active_batches: {
        Row: {
          activated_at: string
          active_batch_id: string
          indicator_id: string
        }
        Insert: {
          activated_at?: string
          active_batch_id: string
          indicator_id: string
        }
        Update: {
          activated_at?: string
          active_batch_id?: string
          indicator_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "indicator_active_batches_active_batch_id_fkey"
            columns: ["active_batch_id"]
            isOneToOne: false
            referencedRelation: "etl_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "indicator_active_batches_indicator_id_fkey"
            columns: ["indicator_id"]
            isOneToOne: true
            referencedRelation: "indicators"
            referencedColumns: ["id"]
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
          batch_id: string | null
          dimensions: Json
          geo_code: string
          id: string
          indicator_id: string
          period: string
          value: number | null
        }
        Insert: {
          batch_id?: string | null
          dimensions?: Json
          geo_code: string
          id?: string
          indicator_id: string
          period: string
          value?: number | null
        }
        Update: {
          batch_id?: string | null
          dimensions?: Json
          geo_code?: string
          id?: string
          indicator_id?: string
          period?: string
          value?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "observations_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "etl_batches"
            referencedColumns: ["id"]
          },
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
      search_index: {
        Row: {
          description: string | null
          id: string
          kind: string
          search_vector: unknown
          title: string
          updated_at: string
          url: string
        }
        Insert: {
          description?: string | null
          id: string
          kind: string
          search_vector?: unknown
          title: string
          updated_at?: string
          url: string
        }
        Update: {
          description?: string | null
          id?: string
          kind?: string
          search_vector?: unknown
          title?: string
          updated_at?: string
          url?: string
        }
        Relationships: []
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
      etl_abort_batch: {
        Args: { p_batch_id: string; p_reason?: string }
        Returns: Json
      }
      etl_cleanup_batches: { Args: { p_older_than?: string }; Returns: number }
      etl_cleanup_failed_batch: {
        Args: { p_batch_id: string; p_max_rows?: number }
        Returns: Json
      }
      etl_finalize_batch: { Args: { p_batch_id: string }; Returns: Json }
      etl_reopen_failed_batch: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      etl_start_batch: {
        Args: {
          p_expected_chunks: number
          p_expected_rows?: number
          p_indicator_id: string
          p_kalla_uppdaterad_datum?: string
          p_run_id?: string
          p_source: string
        }
        Returns: string
      }
      etl_start_period_batch: {
        Args: {
          p_expected_chunks: number
          p_expected_rows: number
          p_indicator_id: string
          p_kalla_uppdaterad_datum?: string
          p_replace_period: string
          p_run_id?: string
          p_source: string
        }
        Returns: string
      }
      etl_store_chunk: {
        Args: {
          p_batch_id: string
          p_checksum: string
          p_chunk_index: number
          p_indicator_id: string
          p_observations: Json
        }
        Returns: Json
      }
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
      search_site: {
        Args: { query_text: string }
        Returns: {
          description: string
          kind: string
          title: string
          url: string
        }[]
      }
    }
    Enums: {
      app_role: "admin" | "editor" | "registered"
      etl_batch_status:
        | "started"
        | "receiving"
        | "ready"
        | "succeeded"
        | "failed"
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
      etl_batch_status: [
        "started",
        "receiving",
        "ready",
        "succeeded",
        "failed",
      ],
      geo_level: ["riket", "län", "kommun"],
      run_status: ["started", "no_change", "succeeded", "failed"],
      visibility_level: ["publik", "inloggad", "admin"],
    },
  },
} as const
