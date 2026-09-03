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
      answer_scale_options: {
        Row: {
          created_at: string
          display_order: number
          label: string
          quiz_version_id: string
          short_label: string
          updated_at: string
          value: number
        }
        Insert: {
          created_at?: string
          display_order: number
          label: string
          quiz_version_id: string
          short_label: string
          updated_at?: string
          value: number
        }
        Update: {
          created_at?: string
          display_order?: number
          label?: string
          quiz_version_id?: string
          short_label?: string
          updated_at?: string
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      campaigns: {
        Row: {
          created_at: string
          description: string | null
          display_order: number
          ends_on: string | null
          id: string
          is_current: boolean
          name: string
          publication_status: string
          published_at: string | null
          short_name: string
          slug: string
          starts_on: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          display_order?: number
          ends_on?: string | null
          id: string
          is_current?: boolean
          name: string
          publication_status?: string
          published_at?: string | null
          short_name: string
          slug: string
          starts_on?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          display_order?: number
          ends_on?: string | null
          id?: string
          is_current?: boolean
          name?: string
          publication_status?: string
          published_at?: string | null
          short_name?: string
          slug?: string
          starts_on?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      candidate_highlights: {
        Row: {
          candidate_id: string
          created_at: string
          display_order: number
          editorial_status: string
          id: string
          metric_text: string | null
          publication_status: string
          published_at: string | null
          summary: string
          theme_id: string
          title: string
          updated_at: string
        }
        Insert: {
          candidate_id: string
          created_at?: string
          display_order: number
          editorial_status?: string
          id: string
          metric_text?: string | null
          publication_status?: string
          published_at?: string | null
          summary: string
          theme_id: string
          title: string
          updated_at?: string
        }
        Update: {
          candidate_id?: string
          created_at?: string
          display_order?: number
          editorial_status?: string
          id?: string
          metric_text?: string | null
          publication_status?: string
          published_at?: string | null
          summary?: string
          theme_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidate_highlights_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_highlights_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["candidate_id"]
          },
          {
            foreignKeyName: "candidate_highlights_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_highlights_theme_id_fkey"
            columns: ["theme_id"]
            isOneToOne: false
            referencedRelation: "themes"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_positions: {
        Row: {
          candidate_id: string
          confidence_id: string
          created_at: string
          documentation_status: string
          id: string
          last_reviewed_at: string
          publication_status: string
          published_at: string | null
          question_id: string
          source_date: string | null
          source_kind_id: string
          stance: number | null
          summary: string
          updated_at: string
        }
        Insert: {
          candidate_id: string
          confidence_id: string
          created_at?: string
          documentation_status: string
          id?: string
          last_reviewed_at: string
          publication_status?: string
          published_at?: string | null
          question_id: string
          source_date?: string | null
          source_kind_id: string
          stance?: number | null
          summary: string
          updated_at?: string
        }
        Update: {
          candidate_id?: string
          confidence_id?: string
          created_at?: string
          documentation_status?: string
          id?: string
          last_reviewed_at?: string
          publication_status?: string
          published_at?: string | null
          question_id?: string
          source_date?: string | null
          source_kind_id?: string
          stance?: number | null
          summary?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidate_positions_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_positions_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["candidate_id"]
          },
          {
            foreignKeyName: "candidate_positions_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_positions_confidence_id_fkey"
            columns: ["confidence_id"]
            isOneToOne: false
            referencedRelation: "confidence_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_positions_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_positions_source_kind_id_fkey"
            columns: ["source_kind_id"]
            isOneToOne: false
            referencedRelation: "source_kinds"
            referencedColumns: ["id"]
          },
        ]
      }
      candidates: {
        Row: {
          accent_key: string
          campaign_id: string
          created_at: string
          display_order: number
          full_name: string
          id: string
          party_id: string
          portrait_asset_id: string | null
          positioning: string
          publication_status: string
          published_at: string | null
          short_bio: string
          short_name: string
          slug: string
          tie_break_order: number
          updated_at: string
        }
        Insert: {
          accent_key: string
          campaign_id: string
          created_at?: string
          display_order: number
          full_name: string
          id: string
          party_id: string
          portrait_asset_id?: string | null
          positioning?: string
          publication_status?: string
          published_at?: string | null
          short_bio?: string
          short_name: string
          slug: string
          tie_break_order: number
          updated_at?: string
        }
        Update: {
          accent_key?: string
          campaign_id?: string
          created_at?: string
          display_order?: number
          full_name?: string
          id?: string
          party_id?: string
          portrait_asset_id?: string | null
          positioning?: string
          publication_status?: string
          published_at?: string | null
          short_bio?: string
          short_name?: string
          slug?: string
          tie_break_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidates_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidates_party_id_fkey"
            columns: ["party_id"]
            isOneToOne: false
            referencedRelation: "parties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidates_portrait_asset_id_fkey"
            columns: ["portrait_asset_id"]
            isOneToOne: false
            referencedRelation: "media_assets"
            referencedColumns: ["id"]
          },
        ]
      }
      community_ranking_counters: {
        Row: {
          candidate_id: string
          created_at: string
          last_counted_at: string | null
          live_match_count: number
          quiz_version_id: string
          updated_at: string
        }
        Insert: {
          candidate_id: string
          created_at?: string
          last_counted_at?: string | null
          live_match_count?: number
          quiz_version_id: string
          updated_at?: string
        }
        Update: {
          candidate_id?: string
          created_at?: string
          last_counted_at?: string | null
          live_match_count?: number
          quiz_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "community_ranking_counters_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "community_ranking_counters_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["candidate_id"]
          },
          {
            foreignKeyName: "community_ranking_counters_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "community_ranking_counters_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "community_ranking_counters_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "community_ranking_counters_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "community_ranking_counters_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      community_ranking_entries: {
        Row: {
          candidate_id: string
          created_at: string
          match_count: number
          snapshot_id: string
          updated_at: string
        }
        Insert: {
          candidate_id: string
          created_at?: string
          match_count?: number
          snapshot_id: string
          updated_at?: string
        }
        Update: {
          candidate_id?: string
          created_at?: string
          match_count?: number
          snapshot_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "community_ranking_entries_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "community_ranking_entries_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["candidate_id"]
          },
          {
            foreignKeyName: "community_ranking_entries_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "community_ranking_entries_snapshot_id_fkey"
            columns: ["snapshot_id"]
            isOneToOne: false
            referencedRelation: "community_ranking_snapshots"
            referencedColumns: ["id"]
          },
        ]
      }
      community_ranking_snapshots: {
        Row: {
          created_at: string
          data_origin: string
          id: string
          is_current: boolean
          label: string
          last_released_at: string | null
          notes: string | null
          publication_status: string
          published_at: string | null
          quiz_version_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          data_origin: string
          id: string
          is_current?: boolean
          label: string
          last_released_at?: string | null
          notes?: string | null
          publication_status?: string
          published_at?: string | null
          quiz_version_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          data_origin?: string
          id?: string
          is_current?: boolean
          label?: string
          last_released_at?: string | null
          notes?: string | null
          publication_status?: string
          published_at?: string | null
          quiz_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "community_ranking_snapshots_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "community_ranking_snapshots_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "community_ranking_snapshots_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "community_ranking_snapshots_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      confidence_levels: {
        Row: {
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          label: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order: number
          id: string
          is_active?: boolean
          label: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          label?: string
          updated_at?: string
        }
        Relationships: []
      }
      highlight_sources: {
        Row: {
          created_at: string
          display_order: number
          highlight_id: string
          source_id: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          highlight_id: string
          source_id: string
        }
        Update: {
          created_at?: string
          display_order?: number
          highlight_id?: string
          source_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "highlight_sources_highlight_id_fkey"
            columns: ["highlight_id"]
            isOneToOne: false
            referencedRelation: "candidate_highlights"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "highlight_sources_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "api_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "highlight_sources_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "sources"
            referencedColumns: ["id"]
          },
        ]
      }
      media_assets: {
        Row: {
          alt_text: string
          bucket_id: string | null
          created_at: string
          credit: string | null
          fallback_url: string | null
          focal_x: number
          focal_y: number
          height: number | null
          id: string
          mime_type: string | null
          object_path: string | null
          publication_status: string
          published_at: string | null
          updated_at: string
          width: number | null
        }
        Insert: {
          alt_text: string
          bucket_id?: string | null
          created_at?: string
          credit?: string | null
          fallback_url?: string | null
          focal_x?: number
          focal_y?: number
          height?: number | null
          id: string
          mime_type?: string | null
          object_path?: string | null
          publication_status?: string
          published_at?: string | null
          updated_at?: string
          width?: number | null
        }
        Update: {
          alt_text?: string
          bucket_id?: string | null
          created_at?: string
          credit?: string | null
          fallback_url?: string | null
          focal_x?: number
          focal_y?: number
          height?: number | null
          id?: string
          mime_type?: string | null
          object_path?: string | null
          publication_status?: string
          published_at?: string | null
          updated_at?: string
          width?: number | null
        }
        Relationships: []
      }
      parties: {
        Row: {
          created_at: string
          display_order: number
          id: string
          name: string
          publication_status: string
          published_at: string | null
          short_name: string | null
          updated_at: string
          website_url: string | null
        }
        Insert: {
          created_at?: string
          display_order?: number
          id: string
          name: string
          publication_status?: string
          published_at?: string | null
          short_name?: string | null
          updated_at?: string
          website_url?: string | null
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          name?: string
          publication_status?: string
          published_at?: string | null
          short_name?: string | null
          updated_at?: string
          website_url?: string | null
        }
        Relationships: []
      }
      position_sources: {
        Row: {
          created_at: string
          display_order: number
          is_primary: boolean
          position_id: string
          source_id: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          is_primary?: boolean
          position_id: string
          source_id: string
        }
        Update: {
          created_at?: string
          display_order?: number
          is_primary?: boolean
          position_id?: string
          source_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "position_sources_position_id_fkey"
            columns: ["position_id"]
            isOneToOne: false
            referencedRelation: "candidate_positions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "position_sources_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "api_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "position_sources_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "sources"
            referencedColumns: ["id"]
          },
        ]
      }
      questions: {
        Row: {
          active_in_quiz: boolean
          code: string
          context: string | null
          created_at: string
          display_order: number
          id: string
          last_reviewed_at: string
          prompt: string
          publication_status: string
          published_at: string | null
          quiz_version_id: string
          theme_id: string
          updated_at: string
        }
        Insert: {
          active_in_quiz?: boolean
          code: string
          context?: string | null
          created_at?: string
          display_order: number
          id?: string
          last_reviewed_at: string
          prompt: string
          publication_status?: string
          published_at?: string | null
          quiz_version_id: string
          theme_id: string
          updated_at?: string
        }
        Update: {
          active_in_quiz?: boolean
          code?: string
          context?: string | null
          created_at?: string
          display_order?: number
          id?: string
          last_reviewed_at?: string
          prompt?: string
          publication_status?: string
          published_at?: string | null
          quiz_version_id?: string
          theme_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questions_theme_id_fkey"
            columns: ["theme_id"]
            isOneToOne: false
            referencedRelation: "themes"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_version_candidates: {
        Row: {
          candidate_id: string
          created_at: string
          display_order: number
          is_active: boolean
          quiz_version_id: string
          tie_break_order: number
          updated_at: string
        }
        Insert: {
          candidate_id: string
          created_at?: string
          display_order: number
          is_active?: boolean
          quiz_version_id: string
          tie_break_order: number
          updated_at?: string
        }
        Update: {
          candidate_id?: string
          created_at?: string
          display_order?: number
          is_active?: boolean
          quiz_version_id?: string
          tie_break_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_version_candidates_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_version_candidates_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["candidate_id"]
          },
          {
            foreignKeyName: "quiz_version_candidates_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_version_candidates_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "quiz_version_candidates_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "quiz_version_candidates_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_version_candidates_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_versions: {
        Row: {
          algorithm_version: string
          archived_at: string | null
          campaign_id: string
          consent_notice_version: string
          created_at: string
          id: string
          important_weight: number
          is_current: boolean
          label: string
          min_comparable_answers: number
          publication_status: string
          published_at: string | null
          stance_max: number
          stance_min: number
          updated_at: string
        }
        Insert: {
          algorithm_version?: string
          archived_at?: string | null
          campaign_id: string
          consent_notice_version: string
          created_at?: string
          id: string
          important_weight?: number
          is_current?: boolean
          label: string
          min_comparable_answers?: number
          publication_status?: string
          published_at?: string | null
          stance_max?: number
          stance_min?: number
          updated_at?: string
        }
        Update: {
          algorithm_version?: string
          archived_at?: string | null
          campaign_id?: string
          consent_notice_version?: string
          created_at?: string
          id?: string
          important_weight?: number
          is_current?: boolean
          label?: string
          min_comparable_answers?: number
          publication_status?: string
          published_at?: string | null
          stance_max?: number
          stance_min?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_versions_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
        ]
      }
      site_settings: {
        Row: {
          created_at: string
          description: string
          is_public: boolean
          key: string
          updated_at: string
          value: Json
        }
        Insert: {
          created_at?: string
          description?: string
          is_public?: boolean
          key: string
          updated_at?: string
          value: Json
        }
        Update: {
          created_at?: string
          description?: string
          is_public?: boolean
          key?: string
          updated_at?: string
          value?: Json
        }
        Relationships: []
      }
      source_candidates: {
        Row: {
          candidate_id: string
          created_at: string
          source_id: string
        }
        Insert: {
          candidate_id: string
          created_at?: string
          source_id: string
        }
        Update: {
          candidate_id?: string
          created_at?: string
          source_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "source_candidates_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_candidates_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["candidate_id"]
          },
          {
            foreignKeyName: "source_candidates_candidate_id_fkey"
            columns: ["candidate_id"]
            isOneToOne: false
            referencedRelation: "candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_candidates_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "api_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_candidates_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "sources"
            referencedColumns: ["id"]
          },
        ]
      }
      source_kinds: {
        Row: {
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          label: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order: number
          id: string
          is_active?: boolean
          label: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          label?: string
          updated_at?: string
        }
        Relationships: []
      }
      source_themes: {
        Row: {
          created_at: string
          source_id: string
          theme_id: string
        }
        Insert: {
          created_at?: string
          source_id: string
          theme_id: string
        }
        Update: {
          created_at?: string
          source_id?: string
          theme_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "source_themes_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "api_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_themes_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_themes_theme_id_fkey"
            columns: ["theme_id"]
            isOneToOne: false
            referencedRelation: "themes"
            referencedColumns: ["id"]
          },
        ]
      }
      sources: {
        Row: {
          archived_at: string | null
          created_at: string
          id: string
          kind_id: string
          notes: string | null
          publication_status: string
          published_at: string | null
          published_on: string
          publisher: string
          title: string
          updated_at: string
          url: string
          verification_status: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          id: string
          kind_id: string
          notes?: string | null
          publication_status?: string
          published_at?: string | null
          published_on: string
          publisher: string
          title: string
          updated_at?: string
          url: string
          verification_status?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          id?: string
          kind_id?: string
          notes?: string | null
          publication_status?: string
          published_at?: string | null
          published_on?: string
          publisher?: string
          title?: string
          updated_at?: string
          url?: string
          verification_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "sources_kind_id_fkey"
            columns: ["kind_id"]
            isOneToOne: false
            referencedRelation: "source_kinds"
            referencedColumns: ["id"]
          },
        ]
      }
      themes: {
        Row: {
          created_at: string
          description: string | null
          display_order: number
          id: string
          label: string
          publication_status: string
          published_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          display_order: number
          id: string
          label: string
          publication_status?: string
          published_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          label?: string
          publication_status?: string
          published_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      api_answer_scale: {
        Row: {
          display_order: number | null
          label: string | null
          quiz_version_id: string | null
          short_label: string | null
          value: number | null
        }
        Relationships: [
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "answer_scale_options_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      api_candidates: {
        Row: {
          accent_key: string | null
          display_order: number | null
          focal_x: number | null
          focal_y: number | null
          full_name: string | null
          highlights: Json | null
          id: string | null
          party: string | null
          portrait: string | null
          portrait_alt: string | null
          portrait_bucket: string | null
          portrait_object_path: string | null
          positioning: string | null
          quiz_version_id: string | null
          short_bio: string | null
          short_name: string | null
          slug: string | null
          tie_break_order: number | null
        }
        Relationships: []
      }
      api_community_rankings: {
        Row: {
          candidate_id: string | null
          collection_enabled: boolean | null
          display_order: number | null
          has_results: boolean | null
          last_released_at: string | null
          match_count: number | null
          match_percentage: number | null
          quiz_version_id: string | null
          rank_position: number | null
          ranking_enabled: boolean | null
          release_batch_size: number | null
          tie_break_order: number | null
          total_match_count: number | null
        }
        Relationships: []
      }
      api_current_quiz: {
        Row: {
          algorithm_version: string | null
          campaign_id: string | null
          consent_notice_version: string | null
          id: string | null
          important_weight: number | null
          label: string | null
          min_comparable_answers: number | null
          published_at: string | null
          stance_max: number | null
          stance_min: number | null
        }
        Relationships: [
          {
            foreignKeyName: "quiz_versions_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
        ]
      }
      api_questions: {
        Row: {
          active_in_quiz: boolean | null
          context: string | null
          display_order: number | null
          id: string | null
          last_reviewed_at: string | null
          positions: Json | null
          prompt: string | null
          theme: string | null
          version: string | null
        }
        Relationships: [
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["version"]
            isOneToOne: false
            referencedRelation: "api_candidates"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["version"]
            isOneToOne: false
            referencedRelation: "api_community_rankings"
            referencedColumns: ["quiz_version_id"]
          },
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["version"]
            isOneToOne: false
            referencedRelation: "api_current_quiz"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questions_quiz_version_id_fkey"
            columns: ["version"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      api_sources: {
        Row: {
          candidate_ids: string[] | null
          date: string | null
          id: string | null
          publisher: string | null
          themes: string[] | null
          title: string | null
          type: string | null
          url: string | null
          verification_status: string | null
        }
        Insert: {
          candidate_ids?: never
          date?: string | null
          id?: string | null
          publisher?: string | null
          themes?: never
          title?: string | null
          type?: string | null
          url?: string | null
          verification_status?: string | null
        }
        Update: {
          candidate_ids?: never
          date?: string | null
          id?: string | null
          publisher?: string | null
          themes?: never
          title?: string | null
          type?: string | null
          url?: string | null
          verification_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sources_kind_id_fkey"
            columns: ["type"]
            isOneToOne: false
            referencedRelation: "source_kinds"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      clone_quiz_version: {
        Args: {
          p_label: string
          p_source_version_id: string
          p_target_version_id: string
        }
        Returns: string
      }
      get_my_staff_profile: {
        Args: never
        Returns: {
          email: string
          role: string
          user_id: string
        }[]
      }
      list_editorial_audit_events: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          actor_email: string
          actor_user_id: string
          id: number
          new_data: Json
          occurred_at: string
          old_data: Json
          operation: string
          row_identity: Json
          table_name: string
          table_schema: string
        }[]
      }
      mark_quiz_version_ready: {
        Args: { p_quiz_version_id: string }
        Returns: string
      }
      publish_quiz_version: {
        Args: { p_quiz_version_id: string; p_snapshot_id: string }
        Returns: string
      }
      record_quiz_result: {
        Args: {
          p_candidate_id: string
          p_quiz_version_id: string
          p_rate_limit_hash: string
          p_receipt_hash: string
        }
        Returns: string
      }
      save_highlight_sources: {
        Args: { p_highlight_id: string; p_source_ids: string[] }
        Returns: string
      }
      save_position_sources: {
        Args: {
          p_position_id: string
          p_primary_source_id?: string
          p_source_ids: string[]
        }
        Returns: string
      }
      save_quiz_composition: {
        Args: {
          p_memberships: Json
          p_quiz_version_id: string
          p_scale_options: Json
        }
        Returns: string
      }
      save_ranking_snapshot: {
        Args: {
          p_counts: Json
          p_data_origin: string
          p_label: string
          p_notes: string
          p_snapshot_id: string
        }
        Returns: string
      }
      save_source_relations: {
        Args: {
          p_candidate_ids: string[]
          p_source_id: string
          p_theme_ids: string[]
        }
        Returns: string
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

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

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
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
