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
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      allowed_user_roles: {
        Row: {
          allowed_user_id: string
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          updated_at: string
        }
        Insert: {
          allowed_user_id: string
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          updated_at?: string
        }
        Update: {
          allowed_user_id?: string
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "allowed_user_roles_allowed_user_id_fkey"
            columns: ["allowed_user_id"]
            isOneToOne: true
            referencedRelation: "allowed_users"
            referencedColumns: ["id"]
          },
        ]
      }
      allowed_users: {
        Row: {
          created_at: string
          departure_date: string | null
          email: string
          first_name: string | null
          id: string
          last_name: string | null
          team: string | null
        }
        Insert: {
          created_at?: string
          departure_date?: string | null
          email: string
          first_name?: string | null
          id?: string
          last_name?: string | null
          team?: string | null
        }
        Update: {
          created_at?: string
          departure_date?: string | null
          email?: string
          first_name?: string | null
          id?: string
          last_name?: string | null
          team?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "allowed_users_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      attachment_deletion_queue: {
        Row: {
          delete_after: string
          id: string
          last_error: string | null
          path: string
          queued_at: string
        }
        Insert: {
          delete_after?: string
          id?: string
          last_error?: string | null
          path: string
          queued_at?: string
        }
        Update: {
          delete_after?: string
          id?: string
          last_error?: string | null
          path?: string
          queued_at?: string
        }
        Relationships: []
      }
      blockers: {
        Row: {
          created_at: string
          department: string
          description: string | null
          id: string
          severity: Database["public"]["Enums"]["blocker_severity"]
          status: Database["public"]["Enums"]["blocker_status"]
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          department?: string
          description?: string | null
          id?: string
          severity?: Database["public"]["Enums"]["blocker_severity"]
          status?: Database["public"]["Enums"]["blocker_status"]
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          department?: string
          description?: string | null
          id?: string
          severity?: Database["public"]["Enums"]["blocker_severity"]
          status?: Database["public"]["Enums"]["blocker_status"]
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      departure_notices: {
        Row: {
          closed_at: string | null
          created_at: string
          departing_label: string
          departing_user_id: string | null
          departure_date: string
          documents: Json
          downloaded_at: string | null
          id: string
          kind: string
          recipient_email: string
          reminder_at: string | null
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          departing_label: string
          departing_user_id?: string | null
          departure_date: string
          documents?: Json
          downloaded_at?: string | null
          id?: string
          kind: string
          recipient_email: string
          reminder_at?: string | null
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          departing_label?: string
          departing_user_id?: string | null
          departure_date?: string
          documents?: Json
          downloaded_at?: string | null
          id?: string
          kind?: string
          recipient_email?: string
          reminder_at?: string | null
        }
        Relationships: []
      }
      manager_teams: {
        Row: {
          allowed_user_id: string
          created_at: string
          id: string
          team: string
        }
        Insert: {
          allowed_user_id: string
          created_at?: string
          id?: string
          team: string
        }
        Update: {
          allowed_user_id?: string
          created_at?: string
          id?: string
          team?: string
        }
        Relationships: [
          {
            foreignKeyName: "manager_teams_allowed_user_id_fkey"
            columns: ["allowed_user_id"]
            isOneToOne: false
            referencedRelation: "allowed_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "manager_teams_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      metrics: {
        Row: {
          key: string
          label: string
          unit: string | null
          updated_at: string
          value: number
        }
        Insert: {
          key: string
          label: string
          unit?: string | null
          updated_at?: string
          value: number
        }
        Update: {
          key?: string
          label?: string
          unit?: string | null
          updated_at?: string
          value?: number
        }
        Relationships: []
      }
      metrics_history: {
        Row: {
          id: string
          metric_key: string
          recorded_at: string
          value: number
        }
        Insert: {
          id?: string
          metric_key: string
          recorded_at?: string
          value: number
        }
        Update: {
          id?: string
          metric_key?: string
          recorded_at?: string
          value?: number
        }
        Relationships: []
      }
      news: {
        Row: {
          author: string
          author_email: string | null
          body: string | null
          created_at: string
          id: string
          image_path: string | null
          links: Json
          revalidate_at: string | null
          status: Database["public"]["Enums"]["news_status"]
          title: string
        }
        Insert: {
          author?: string
          author_email?: string | null
          body?: string | null
          created_at?: string
          id?: string
          image_path?: string | null
          links?: Json
          revalidate_at?: string | null
          status?: Database["public"]["Enums"]["news_status"]
          title: string
        }
        Update: {
          author?: string
          author_email?: string | null
          body?: string | null
          created_at?: string
          id?: string
          image_path?: string | null
          links?: Json
          revalidate_at?: string | null
          status?: Database["public"]["Enums"]["news_status"]
          title?: string
        }
        Relationships: []
      }
      submission_status_history: {
        Row: {
          changed_at: string
          changed_by_email: string | null
          changed_by_name: string | null
          id: string
          is_automatic: boolean
          new_status: Database["public"]["Enums"]["submission_status"]
          old_status: Database["public"]["Enums"]["submission_status"] | null
          rejection_category:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note: string | null
          submission_id: string
        }
        Insert: {
          changed_at?: string
          changed_by_email?: string | null
          changed_by_name?: string | null
          id?: string
          is_automatic?: boolean
          new_status: Database["public"]["Enums"]["submission_status"]
          old_status?: Database["public"]["Enums"]["submission_status"] | null
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          submission_id: string
        }
        Update: {
          changed_at?: string
          changed_by_email?: string | null
          changed_by_name?: string | null
          id?: string
          is_automatic?: boolean
          new_status?: Database["public"]["Enums"]["submission_status"]
          old_status?: Database["public"]["Enums"]["submission_status"] | null
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          submission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "submission_status_history_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      submissions: {
        Row: {
          attachment_name: string | null
          attachment_path: string | null
          author_name: string
          content: string
          created_at: string
          id: string
          rejection_category:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note: string | null
          revalidate_at: string | null
          status: Database["public"]["Enums"]["submission_status"]
          submitted_by_email: string | null
          team: string
        }
        Insert: {
          attachment_name?: string | null
          attachment_path?: string | null
          author_name: string
          content: string
          created_at?: string
          id?: string
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          revalidate_at?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          submitted_by_email?: string | null
          team: string
        }
        Update: {
          attachment_name?: string | null
          attachment_path?: string | null
          author_name?: string
          content?: string
          created_at?: string
          id?: string
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          revalidate_at?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          submitted_by_email?: string | null
          team?: string
        }
        Relationships: [
          {
            foreignKeyName: "submissions_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      teams: {
        Row: {
          created_at: string
          is_reserved: boolean
          name: string
        }
        Insert: {
          created_at?: string
          is_reserved?: boolean
          name: string
        }
        Update: {
          created_at?: string
          is_reserved?: boolean
          name?: string
        }
        Relationships: []
      }
    }
    Views: {
      metrics_with_trend: {
        Row: {
          delta: number | null
          key: string | null
          label: string | null
          previous_value: number | null
          trend: string | null
          unit: string | null
          updated_at: string | null
          value: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      choisir_mon_role: {
        Args: {
          _first_name: string
          _last_name: string
          _role: Database["public"]["Enums"]["app_role"]
          _team?: string | null
        }
        Returns: Database["public"]["Enums"]["app_role"]
      }
      bulk_import_allowed_users: {
        Args: { _dry_run?: boolean; _rows: Json }
        Returns: Json
      }
      mark_departure_notice_downloaded: {
        Args: { _id: string }
        Returns: undefined
      }
    }
    Enums: {
      app_role: "admin" | "manager" | "collaborateur"
      blocker_severity: "critical" | "warning" | "info"
      blocker_status: "OUVERT" | "EN COURS" | "SURVEILLANCE" | "RÉSOLU"
      news_status: "brouillon" | "publiée"
      rejection_category:
        | "à clarifier"
        | "en désaccord avec les process"
        | "doublon"
        | "autre"
      submission_status: "en attente" | "validée" | "refusée"
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
      app_role: ["admin", "manager", "collaborateur"],
      blocker_severity: ["critical", "warning", "info"],
      blocker_status: ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"],
      news_status: ["brouillon", "publiée"],
      rejection_category: [
        "à clarifier",
        "en désaccord avec les process",
        "doublon",
        "autre",
      ],
      submission_status: ["en attente", "validée", "refusée"],
    },
  },
} as const
