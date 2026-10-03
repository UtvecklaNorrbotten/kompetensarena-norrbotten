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
      af_revision_fingerprints: {
        Row: {
          checked_at: string
          checksum: string
          period: string
          row_count: number
          source_manifest: Json
          source_release_period: string | null
          target: string
        }
        Insert: {
          checked_at?: string
          checksum: string
          period: string
          row_count: number
          source_manifest?: Json
          source_release_period?: string | null
          target: string
        }
        Update: {
          checked_at?: string
          checksum?: string
          period?: string
          row_count?: number
          source_manifest?: Json
          source_release_period?: string | null
          target?: string
        }
        Relationships: []
      }
      afr_ae_current: {
        Row: {
          ae_stat: number | null
          ae_typ: number | null
          anst_kl: number | null
          cfar_nr: number
          current_history_id: number | null
          first_seen_at: string
          hj_verks_je: number | null
          in_source: boolean
          je_id: string | null
          kommun: string | null
          lan: string | null
          nord_sw: number | null
          ost_sw: number | null
          primary_sni: string | null
          removed_observed_at: string | null
          row_hash: string
          slut_dat: string | null
          start_dat: string | null
          sync_id: string
          tat_ort_sma_ort_ben: string | null
          tat_ort_sma_ort_kod: string | null
          tat_sma_typ_kod: string | null
        }
        Insert: {
          ae_stat?: number | null
          ae_typ?: number | null
          anst_kl?: number | null
          cfar_nr: number
          current_history_id?: number | null
          first_seen_at?: string
          hj_verks_je?: number | null
          in_source?: boolean
          je_id?: string | null
          kommun?: string | null
          lan?: string | null
          nord_sw?: number | null
          ost_sw?: number | null
          primary_sni?: string | null
          removed_observed_at?: string | null
          row_hash: string
          slut_dat?: string | null
          start_dat?: string | null
          sync_id: string
          tat_ort_sma_ort_ben?: string | null
          tat_ort_sma_ort_kod?: string | null
          tat_sma_typ_kod?: string | null
        }
        Update: {
          ae_stat?: number | null
          ae_typ?: number | null
          anst_kl?: number | null
          cfar_nr?: number
          current_history_id?: number | null
          first_seen_at?: string
          hj_verks_je?: number | null
          in_source?: boolean
          je_id?: string | null
          kommun?: string | null
          lan?: string | null
          nord_sw?: number | null
          ost_sw?: number | null
          primary_sni?: string | null
          removed_observed_at?: string | null
          row_hash?: string
          slut_dat?: string | null
          start_dat?: string | null
          sync_id?: string
          tat_ort_sma_ort_ben?: string | null
          tat_ort_sma_ort_kod?: string | null
          tat_sma_typ_kod?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "afr_ae_current_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "afr_je_ident"
            referencedColumns: ["je_id"]
          },
          {
            foreignKeyName: "afr_ae_current_sync_id_fkey"
            columns: ["sync_id"]
            isOneToOne: false
            referencedRelation: "afr_syncs"
            referencedColumns: ["id"]
          },
        ]
      }
      afr_ae_history: {
        Row: {
          ae_stat: number | null
          ae_typ: number | null
          anst_kl: number | null
          cfar_nr: number
          change_types: string[]
          history_id: number
          hj_verks_je: number | null
          in_source: boolean
          je_id: string | null
          kommun: string | null
          lan: string | null
          nord_sw: number | null
          ost_sw: number | null
          row_hash: string
          slut_dat: string | null
          sni: Json | null
          start_dat: string | null
          sync_id: string
          tat_ort_sma_ort_ben: string | null
          tat_ort_sma_ort_kod: string | null
          tat_sma_typ_kod: string | null
          valid_from: string
          valid_to: string | null
        }
        Insert: {
          ae_stat?: number | null
          ae_typ?: number | null
          anst_kl?: number | null
          cfar_nr: number
          change_types: string[]
          history_id?: never
          hj_verks_je?: number | null
          in_source?: boolean
          je_id?: string | null
          kommun?: string | null
          lan?: string | null
          nord_sw?: number | null
          ost_sw?: number | null
          row_hash: string
          slut_dat?: string | null
          sni?: Json | null
          start_dat?: string | null
          sync_id: string
          tat_ort_sma_ort_ben?: string | null
          tat_ort_sma_ort_kod?: string | null
          tat_sma_typ_kod?: string | null
          valid_from: string
          valid_to?: string | null
        }
        Update: {
          ae_stat?: number | null
          ae_typ?: number | null
          anst_kl?: number | null
          cfar_nr?: number
          change_types?: string[]
          history_id?: never
          hj_verks_je?: number | null
          in_source?: boolean
          je_id?: string | null
          kommun?: string | null
          lan?: string | null
          nord_sw?: number | null
          ost_sw?: number | null
          row_hash?: string
          slut_dat?: string | null
          sni?: Json | null
          start_dat?: string | null
          sync_id?: string
          tat_ort_sma_ort_ben?: string | null
          tat_ort_sma_ort_kod?: string | null
          tat_sma_typ_kod?: string | null
          valid_from?: string
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "afr_ae_history_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "afr_je_ident"
            referencedColumns: ["je_id"]
          },
          {
            foreignKeyName: "afr_ae_history_sync_id_fkey"
            columns: ["sync_id"]
            isOneToOne: false
            referencedRelation: "afr_syncs"
            referencedColumns: ["id"]
          },
        ]
      }
      afr_ae_sni_current: {
        Row: {
          andel_procent: number | null
          avdelnings_kod: string | null
          cfar_nr: number
          naringsgren: string
          rangordning: number
        }
        Insert: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          cfar_nr: number
          naringsgren: string
          rangordning: number
        }
        Update: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          cfar_nr?: number
          naringsgren?: string
          rangordning?: number
        }
        Relationships: [
          {
            foreignKeyName: "afr_ae_sni_current_cfar_nr_fkey"
            columns: ["cfar_nr"]
            isOneToOne: false
            referencedRelation: "afr_ae_analysis"
            referencedColumns: ["cfar_nr"]
          },
          {
            foreignKeyName: "afr_ae_sni_current_cfar_nr_fkey"
            columns: ["cfar_nr"]
            isOneToOne: false
            referencedRelation: "afr_ae_current"
            referencedColumns: ["cfar_nr"]
          },
        ]
      }
      afr_ae_sni_history: {
        Row: {
          andel_procent: number | null
          avdelnings_kod: string | null
          history_id: number
          naringsgren: string
          rangordning: number
        }
        Insert: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          history_id: number
          naringsgren: string
          rangordning: number
        }
        Update: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          history_id?: number
          naringsgren?: string
          rangordning?: number
        }
        Relationships: [
          {
            foreignKeyName: "afr_ae_sni_history_history_id_fkey"
            columns: ["history_id"]
            isOneToOne: false
            referencedRelation: "afr_ae_history"
            referencedColumns: ["history_id"]
          },
        ]
      }
      afr_agkat_group: {
        Row: {
          ag_kat: string
          grupp: string
        }
        Insert: {
          ag_kat: string
          grupp: string
        }
        Update: {
          ag_kat?: string
          grupp?: string
        }
        Relationships: []
      }
      afr_code_value_history: {
        Row: {
          change: string
          id: number
          kod: string
          new_extra: Json | null
          new_klartext: string | null
          observed_at: string
          old_extra: Json | null
          old_klartext: string | null
          table_name: string
        }
        Insert: {
          change: string
          id?: never
          kod: string
          new_extra?: Json | null
          new_klartext?: string | null
          observed_at?: string
          old_extra?: Json | null
          old_klartext?: string | null
          table_name: string
        }
        Update: {
          change?: string
          id?: never
          kod?: string
          new_extra?: Json | null
          new_klartext?: string | null
          observed_at?: string
          old_extra?: Json | null
          old_klartext?: string | null
          table_name?: string
        }
        Relationships: []
      }
      afr_code_values: {
        Row: {
          active: boolean
          extra: Json
          first_seen_at: string
          klartext: string | null
          kod: string
          table_name: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          extra?: Json
          first_seen_at?: string
          klartext?: string | null
          kod: string
          table_name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          extra?: Json
          first_seen_at?: string
          klartext?: string | null
          kod?: string
          table_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      afr_deferred_ddl: {
        Row: {
          ddl: string
          name: string
          ord: number
        }
        Insert: {
          ddl: string
          name: string
          ord: number
        }
        Update: {
          ddl?: string
          name?: string
          ord?: number
        }
        Relationships: []
      }
      afr_je_current: {
        Row: {
          ae_ant: number | null
          ag_kat: string | null
          anst_kl: string | null
          arb_giv_stat: string | null
          bol_stat: string | null
          current_history_id: number | null
          f_skatt_stat: string | null
          first_seen_at: string
          ftg_stat: string | null
          in_source: boolean
          je_id: string
          jurform: string | null
          kommun_sate: string | null
          lan_sate: string | null
          moms_stat: string | null
          oms_ar: number | null
          oms_kl: string | null
          primary_sni: string | null
          priv_publ: string | null
          reg_dat: string | null
          removed_observed_at: string | null
          row_hash: string
          sektor: string | null
          slut_dat: string | null
          start_dat: string | null
          sync_id: string
        }
        Insert: {
          ae_ant?: number | null
          ag_kat?: string | null
          anst_kl?: string | null
          arb_giv_stat?: string | null
          bol_stat?: string | null
          current_history_id?: number | null
          f_skatt_stat?: string | null
          first_seen_at?: string
          ftg_stat?: string | null
          in_source?: boolean
          je_id: string
          jurform?: string | null
          kommun_sate?: string | null
          lan_sate?: string | null
          moms_stat?: string | null
          oms_ar?: number | null
          oms_kl?: string | null
          primary_sni?: string | null
          priv_publ?: string | null
          reg_dat?: string | null
          removed_observed_at?: string | null
          row_hash: string
          sektor?: string | null
          slut_dat?: string | null
          start_dat?: string | null
          sync_id: string
        }
        Update: {
          ae_ant?: number | null
          ag_kat?: string | null
          anst_kl?: string | null
          arb_giv_stat?: string | null
          bol_stat?: string | null
          current_history_id?: number | null
          f_skatt_stat?: string | null
          first_seen_at?: string
          ftg_stat?: string | null
          in_source?: boolean
          je_id?: string
          jurform?: string | null
          kommun_sate?: string | null
          lan_sate?: string | null
          moms_stat?: string | null
          oms_ar?: number | null
          oms_kl?: string | null
          primary_sni?: string | null
          priv_publ?: string | null
          reg_dat?: string | null
          removed_observed_at?: string | null
          row_hash?: string
          sektor?: string | null
          slut_dat?: string | null
          start_dat?: string | null
          sync_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "afr_je_current_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: true
            referencedRelation: "afr_je_ident"
            referencedColumns: ["je_id"]
          },
          {
            foreignKeyName: "afr_je_current_sync_id_fkey"
            columns: ["sync_id"]
            isOneToOne: false
            referencedRelation: "afr_syncs"
            referencedColumns: ["id"]
          },
        ]
      }
      afr_je_history: {
        Row: {
          ae_ant: number | null
          ag_kat: string | null
          anst_kl: string | null
          arb_giv_stat: string | null
          bol_stat: string | null
          change_types: string[]
          f_skatt_stat: string | null
          ftg_stat: string | null
          history_id: number
          in_source: boolean
          je_id: string
          jurform: string | null
          kommun_sate: string | null
          lan_sate: string | null
          moms_stat: string | null
          oms_ar: number | null
          oms_kl: string | null
          priv_publ: string | null
          reg_dat: string | null
          row_hash: string
          sektor: string | null
          slut_dat: string | null
          sni: Json | null
          start_dat: string | null
          sync_id: string
          valid_from: string
          valid_to: string | null
        }
        Insert: {
          ae_ant?: number | null
          ag_kat?: string | null
          anst_kl?: string | null
          arb_giv_stat?: string | null
          bol_stat?: string | null
          change_types: string[]
          f_skatt_stat?: string | null
          ftg_stat?: string | null
          history_id?: never
          in_source?: boolean
          je_id: string
          jurform?: string | null
          kommun_sate?: string | null
          lan_sate?: string | null
          moms_stat?: string | null
          oms_ar?: number | null
          oms_kl?: string | null
          priv_publ?: string | null
          reg_dat?: string | null
          row_hash: string
          sektor?: string | null
          slut_dat?: string | null
          sni?: Json | null
          start_dat?: string | null
          sync_id: string
          valid_from: string
          valid_to?: string | null
        }
        Update: {
          ae_ant?: number | null
          ag_kat?: string | null
          anst_kl?: string | null
          arb_giv_stat?: string | null
          bol_stat?: string | null
          change_types?: string[]
          f_skatt_stat?: string | null
          ftg_stat?: string | null
          history_id?: never
          in_source?: boolean
          je_id?: string
          jurform?: string | null
          kommun_sate?: string | null
          lan_sate?: string | null
          moms_stat?: string | null
          oms_ar?: number | null
          oms_kl?: string | null
          priv_publ?: string | null
          reg_dat?: string | null
          row_hash?: string
          sektor?: string | null
          slut_dat?: string | null
          sni?: Json | null
          start_dat?: string | null
          sync_id?: string
          valid_from?: string
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "afr_je_history_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "afr_je_ident"
            referencedColumns: ["je_id"]
          },
          {
            foreignKeyName: "afr_je_history_sync_id_fkey"
            columns: ["sync_id"]
            isOneToOne: false
            referencedRelation: "afr_syncs"
            referencedColumns: ["id"]
          },
        ]
      }
      afr_je_ident: {
        Row: {
          first_seen_at: string
          je_id: string
          org_nr: string | null
          pe_org_nr: string
        }
        Insert: {
          first_seen_at?: string
          je_id?: string
          org_nr?: string | null
          pe_org_nr: string
        }
        Update: {
          first_seen_at?: string
          je_id?: string
          org_nr?: string | null
          pe_org_nr?: string
        }
        Relationships: []
      }
      afr_je_sni_current: {
        Row: {
          andel_procent: number | null
          avdelnings_kod: string | null
          je_id: string
          naringsgren: string
          rangordning: number
        }
        Insert: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          je_id: string
          naringsgren: string
          rangordning: number
        }
        Update: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          je_id?: string
          naringsgren?: string
          rangordning?: number
        }
        Relationships: [
          {
            foreignKeyName: "afr_je_sni_current_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "afr_je_current"
            referencedColumns: ["je_id"]
          },
        ]
      }
      afr_je_sni_history: {
        Row: {
          andel_procent: number | null
          avdelnings_kod: string | null
          history_id: number
          naringsgren: string
          rangordning: number
        }
        Insert: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          history_id: number
          naringsgren: string
          rangordning: number
        }
        Update: {
          andel_procent?: number | null
          avdelnings_kod?: string | null
          history_id?: number
          naringsgren?: string
          rangordning?: number
        }
        Relationships: [
          {
            foreignKeyName: "afr_je_sni_history_history_id_fkey"
            columns: ["history_id"]
            isOneToOne: false
            referencedRelation: "afr_je_history"
            referencedColumns: ["history_id"]
          },
        ]
      }
      afr_stage_records: {
        Row: {
          entity: string
          key: string
          op: string
          payload: Json | null
          row_hash: string | null
          sync_id: string
        }
        Insert: {
          entity: string
          key: string
          op: string
          payload?: Json | null
          row_hash?: string | null
          sync_id: string
        }
        Update: {
          entity?: string
          key?: string
          op?: string
          payload?: Json | null
          row_hash?: string | null
          sync_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "afr_stage_records_sync_id_fkey"
            columns: ["sync_id"]
            isOneToOne: false
            referencedRelation: "afr_syncs"
            referencedColumns: ["id"]
          },
        ]
      }
      afr_sync_chunks: {
        Row: {
          checksum: string
          chunk_index: number
          created_at: string
          entity: string
          removed_count: number
          row_count: number
          sync_id: string
        }
        Insert: {
          checksum: string
          chunk_index: number
          created_at?: string
          entity: string
          removed_count?: number
          row_count: number
          sync_id: string
        }
        Update: {
          checksum?: string
          chunk_index?: number
          created_at?: string
          entity?: string
          removed_count?: number
          row_count?: number
          sync_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "afr_sync_chunks_sync_id_fkey"
            columns: ["sync_id"]
            isOneToOne: false
            referencedRelation: "afr_syncs"
            referencedColumns: ["id"]
          },
        ]
      }
      afr_syncs: {
        Row: {
          ae_source_count: number
          api_version: string | null
          confirm_large_removal: boolean
          created_at: string
          error_message: string | null
          expected_ae_chunks: number
          expected_je_chunks: number
          fetched_at: string
          finalized_at: string | null
          id: string
          je_source_count: number
          last_activity_at: string
          mode: string
          received_ae_chunks: number
          received_je_chunks: number
          run_id: string | null
          source_date: string
          stats: Json
          status: string
        }
        Insert: {
          ae_source_count: number
          api_version?: string | null
          confirm_large_removal?: boolean
          created_at?: string
          error_message?: string | null
          expected_ae_chunks: number
          expected_je_chunks: number
          fetched_at: string
          finalized_at?: string | null
          id?: string
          je_source_count: number
          last_activity_at?: string
          mode: string
          received_ae_chunks?: number
          received_je_chunks?: number
          run_id?: string | null
          source_date: string
          stats?: Json
          status?: string
        }
        Update: {
          ae_source_count?: number
          api_version?: string | null
          confirm_large_removal?: boolean
          created_at?: string
          error_message?: string | null
          expected_ae_chunks?: number
          expected_je_chunks?: number
          fetched_at?: string
          finalized_at?: string | null
          id?: string
          je_source_count?: number
          last_activity_at?: string
          mode?: string
          received_ae_chunks?: number
          received_je_chunks?: number
          run_id?: string | null
          source_date?: string
          stats?: Json
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "afr_syncs_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "data_source_runs"
            referencedColumns: ["id"]
          },
        ]
      }
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
      afr_ae_analysis: {
        Row: {
          ae_stat: number | null
          ae_typ: number | null
          ag_kat: string | null
          agarkontroll_grupp: string | null
          anst_kl: number | null
          cfar_nr: number | null
          hj_verks_je: number | null
          je_id: string | null
          jurform: string | null
          kommun: string | null
          kommun_sate: string | null
          lan: string | null
          lan_sate: string | null
          primar_sni: string | null
          sate_utanfor_lan: boolean | null
          sektor: string | null
          tat_ort_sma_ort_kod: string | null
          tat_sma_typ_kod: string | null
        }
        Relationships: [
          {
            foreignKeyName: "afr_ae_current_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "afr_je_ident"
            referencedColumns: ["je_id"]
          },
        ]
      }
    }
    Functions: {
      afr_abort_sync: {
        Args: { p_reason?: string; p_sync_id: string }
        Returns: Json
      }
      afr_ae_canonical: { Args: { p: Json }; Returns: string }
      afr_assert_deferred_ready: { Args: never; Returns: undefined }
      afr_backfill_primary_sni: {
        Args: { p_from_page: number; p_pages?: number }
        Returns: Json
      }
      afr_canonical_sni: { Args: { p: Json }; Returns: string }
      afr_cleanup_failed_initial: {
        Args: { p_max_rows?: number; p_sync_id: string }
        Returns: Json
      }
      afr_current_hashes: {
        Args: { p_after?: string; p_entity: string; p_limit?: number }
        Returns: Json
      }
      afr_finalize_sync: {
        Args: { p_stats?: Json; p_sync_id: string }
        Returns: Json
      }
      afr_hash: { Args: { p_text: string }; Returns: string }
      afr_je_canonical: { Args: { p: Json }; Returns: string }
      afr_missing_deferred: { Args: never; Returns: string[] }
      afr_rebuild_deferred: { Args: never; Returns: Json }
      afr_reopen_initial_sync: { Args: { p_sync_id: string }; Returns: Json }
      afr_sni_primary: { Args: { snap: Json }; Returns: string }
      afr_sni_snapshot: { Args: { p: Json }; Returns: Json }
      afr_start_sync: {
        Args: {
          p_ae_source_count: number
          p_api_version: string
          p_confirm_large_removal?: boolean
          p_details?: Json
          p_expected_ae_chunks: number
          p_expected_je_chunks: number
          p_fetched_at: string
          p_je_source_count: number
          p_mode: string
          p_source_date: string
        }
        Returns: string
      }
      afr_store_chunk: {
        Args: {
          p_checksum: string
          p_chunk_index: number
          p_entity: string
          p_records: Json
          p_removed: Json
          p_sync_id: string
        }
        Returns: Json
      }
      afr_sync_code_table: {
        Args: { p_rows: Json; p_table: string }
        Returns: Json
      }
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
      etl_reopen_failed_batch: { Args: { p_batch_id: string }; Returns: Json }
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
