import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ErrorSummary,
  Field,
  FormActions,
  Modal,
  Select,
  TextArea,
} from "@/components/manage/crud-ui";
import { CharCounter, formatExactDate, rejectionErrorMessage } from "@/components/expandable-card";
import { newSubmissionSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import {
  SEVERITY_LABELS,
  submitSubmission,
  type BlockerSeverity,
  type SubmissionKind,
} from "@/lib/dashboard";
import {
  ADMIN_LABEL,
  assigneeHint,
  assigneeLine,
  fetchAssigneeNames,
  fetchMyProfile,
  fetchSelectableTeamNames,
  resubmitSubmission,
  trackEvent,
  type MySubmission,
} from "@/lib/f1";
import { toast } from "sonner";

const KIND_CHOICES: { kind: SubmissionKind; title: string; help: string }[] = [
  { kind: "idée", title: "Idée", help: "Une idée, une demande ou une question" },
  { kind: "point bloquant", title: "Point bloquant", help: "Un problème qui freine le travail" },
];

export type SentSubmission = { kind: SubmissionKind; assignedTo: string };

/**
 * Formulaire « Soumettre » : type, personne assignée, description, sévérité (US29, US30).
 * US68 : avec `resubmit`, le même formulaire modifie une soumission refusée et la renvoie.
 * Tout se modifie sauf l'équipe ; le circuit est celui d'un envoi.
 * 2026-11-04 : l'admin choisit l'équipe concernée (obligatoire), comme un manager de plusieurs
 * équipes ; la soumission suit alors le circuit de cette équipe (US30).
 */
export function SubmitModal({
  role,
  email,
  managerTeams,
  onClose,
  onSent,
  resubmit,
}: {
  role: string;
  email: string;
  managerTeams: string[];
  onClose: () => void;
  onSent: (sent: SentSubmission) => void;
  resubmit?: MySubmission;
}) {
  const qc = useQueryClient();
  const openedAt = useRef(Date.now());
  const [kind, setKind] = useState<SubmissionKind | null>(resubmit?.kind ?? null);
  const [severity, setSeverity] = useState<BlockerSeverity | "">(resubmit?.severity ?? "");
  const [content, setContent] = useState(resubmit?.content ?? "");
  const [team, setTeam] = useState(
    resubmit ? resubmit.team : managerTeams.length === 1 ? managerTeams[0] : "",
  );
  const [attachment, setAttachment] = useState<File | null>(null);
  const [keepAttachment, setKeepAttachment] = useState(!!resubmit?.attachment_path);
  const [errors, setErrors] = useState<FieldErrors>({});

  const profile = useQuery({
    queryKey: ["profile", email],
    queryFn: () => fetchMyProfile(email),
    retry: false,
  });
  useEffect(() => {
    if (!team && managerTeams.length === 1) setTeam(managerTeams[0]);
  }, [managerTeams, team]);

  const isAdmin = role === "admin";
  const choosesTeam = !resubmit && (isAdmin || role === "manager");
  const adminTeams = useQuery({
    queryKey: ["teams", "selectable"],
    queryFn: fetchSelectableTeamNames,
    enabled: !resubmit && isAdmin,
    retry: false,
  });
  const teamChoices = isAdmin ? (adminTeams.data ?? []) : managerTeams;

  const ownTeam = resubmit
    ? resubmit.team
    : choosesTeam
      ? team
      : (profile.data?.team ?? "");
  const assignees = useQuery({
    queryKey: ["assignees", role, ownTeam],
    queryFn: () => fetchAssigneeNames(ownTeam || null),
    enabled: !!kind && (!choosesTeam || !!team),
    retry: false,
  });
  const managers = assignees.data ?? [];
  const assigned = kind ? assigneeLine(kind, managers) : "";

  const submit = useMutation({
    mutationFn: (input: Parameters<typeof submitSubmission>[0]) =>
      resubmit
        ? resubmitSubmission(
            {
              id: resubmit.id,
              kind: input.kind,
              severity: input.severity ?? null,
              content: input.content,
              keptAttachment:
                keepAttachment && resubmit.attachment_path
                  ? { path: resubmit.attachment_path, name: resubmit.attachment_name ?? null }
                  : null,
            },
            attachment,
          )
        : submitSubmission(input, attachment),
    onSuccess: (_d, input) => {
      if (!resubmit) {
        trackEvent("submission_sent", "soumettre", {
          kind: input.kind,
          seconds: Math.round((Date.now() - openedAt.current) / 1000),
        });
      }
      qc.invalidateQueries({ queryKey: ["submissions"] });
      onSent({ kind: input.kind, assignedTo: assigned });
    },
    onError: (e: unknown) => toast.error(rejectionErrorMessage(e)),
  });

  function choose(next: SubmissionKind) {
    setKind(next);
    setErrors((e) => {
      const { kind: _k, ...rest } = e;
      return rest;
    });
    trackEvent("submission_type_selected", "soumettre", { kind: next });
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const result = validate(newSubmissionSchema, {
      kind,
      severity: kind === "point bloquant" && severity ? severity : null,
      author_name: resubmit ? resubmit.author_name : (profile.data?.fullName ?? ""),
      team: resubmit ? resubmit.team : choosesTeam ? team : (profile.data?.team ?? ""),
      content,
    });
    if (!result.ok) {
      setErrors(result.errors);
      return;
    }
    setErrors({});
    submit.mutate(result.data);
  }

  // L'admin signe au nom de l'administration ; l'équipe choisie est celle de la soumission.
  const teamLabel =
    isAdmin || ownTeam === "Admin" ? ADMIN_LABEL : ownTeam || "équipe à choisir";

  return (
    <Modal title={resubmit ? "Modifier et renvoyer" : "Soumettre"} onClose={onClose}>
      <form onSubmit={onSubmit} className="space-y-md" noValidate>
        <ErrorSummary errors={errors} />

        {resubmit && (
          <div className="p-sm bg-error-container text-on-error-container text-body-sm wrap-anywhere space-y-1">
            <p className="font-bold">
              Refusée le {formatExactDate(resubmit.last_change_at)}
              {resubmit.rejection_category ? ` · Motif : ${resubmit.rejection_category}` : ""}
            </p>
            {resubmit.rejection_note && (
              <p className="whitespace-pre-line">Raison : {resubmit.rejection_note}</p>
            )}
            <p>
              Modifiez ce qui doit l'être, puis renvoyez : la soumission repart en attente, comme un
              nouvel envoi.
            </p>
          </div>
        )}

        <div className="bg-surface-container-low p-sm space-y-1">
          <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">Auteur</p>
          <p className="font-body-md text-primary font-bold">
            {profile.data?.fullName ?? "…"} · {teamLabel}
          </p>
          <p className="text-body-sm text-on-surface-variant">Repris de votre compte.</p>
        </div>

        {choosesTeam && (isAdmin || managerTeams.length > 1) && (
          <Field label="Équipe concernée *" error={errors.team}>
            <Select value={team} onChange={(e) => setTeam(e.target.value)}>
              <option value="">
                {isAdmin ? "Choisis l'équipe concernée" : "Choisis une de tes équipes"}
              </option>
              {teamChoices.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <fieldset className="space-y-xs">
          <legend className="font-label-sm text-label-sm text-on-surface-variant uppercase">
            Type de soumission *
          </legend>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-sm">
            {KIND_CHOICES.map((c) => {
              const selected = kind === c.kind;
              return (
                <label
                  key={c.kind}
                  className={`flex cursor-pointer items-start gap-sm border p-sm focus-within:ring-2 focus-within:ring-primary ${
                    selected
                      ? "border-2 border-primary bg-card"
                      : "border-outline-variant bg-card hover:bg-surface-container"
                  }`}
                >
                  <input
                    type="radio"
                    name="submission-kind"
                    value={c.kind}
                    checked={selected}
                    onChange={() => choose(c.kind)}
                    className="sr-only"
                  />
                  <span
                    aria-hidden="true"
                    className={`mt-1 inline-block h-4 w-4 shrink-0 rounded-full border ${
                      selected
                        ? "border-primary bg-primary ring-2 ring-inset ring-card"
                        : "border-outline"
                    }`}
                  />
                  <span className="min-w-0">
                    <span className="block font-body-md text-primary font-bold">{c.title}</span>
                    <span className="block text-body-sm text-on-surface-variant">{c.help}</span>
                  </span>
                </label>
              );
            })}
          </div>
          {errors.kind && (
            <p role="alert" className="text-body-sm text-error">
              {errors.kind}
            </p>
          )}
        </fieldset>

        {kind && (
          <div className="space-y-1" aria-live="polite">
            <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">
              Assigné à
            </p>
            {choosesTeam && !team ? (
              <p className="text-body-sm text-on-surface-variant">
                Choisis d'abord l'équipe concernée.
              </p>
            ) : assignees.isLoading ? (
              <p className="text-body-sm text-on-surface-variant">Chargement…</p>
            ) : (
              <>
                <p className="font-body-md text-primary">{assigned || ADMIN_LABEL}</p>
                <p className="text-body-sm text-on-surface-variant">
                  {ownTeam === "Admin"
                    ? "L'administration examinera votre soumission."
                    : assigneeHint(kind, managers, isAdmin)}
                </p>
              </>
            )}
          </div>
        )}

        <Field label="Description *" error={errors.content}>
          <TextArea
            rows={5}
            value={content}
            aria-label="Description"
            aria-describedby="soumettre-description-aide"
            placeholder={
              kind === "point bloquant"
                ? "Décris ce qui bloque ton travail et depuis quand…"
                : "Décris ton idée, ta demande ou ta question…"
            }
            onChange={(e) => setContent(e.target.value)}
          />
          <CharCounter value={content} max={2000} min={5} />
          {/* Aide de la décision du 2026-11-01 : minimiser les noms envoyés à l'IA (US29, R8). */}
          <p id="soumettre-description-aide" className="text-body-sm text-on-surface-variant">
            Décris la situation sans nommer de collègue ni de candidat : indique plutôt son rôle ou
            son équipe. Ce texte peut être résumé par une IA.
          </p>
        </Field>

        {kind === "point bloquant" && (
          <Field label="Sévérité *" error={errors.severity}>
            <Select
              value={severity}
              onChange={(e) => setSeverity(e.target.value as BlockerSeverity | "")}
            >
              <option value="">Choisis une sévérité</option>
              {(Object.keys(SEVERITY_LABELS) as BlockerSeverity[]).map((s) => (
                <option key={s} value={s}>
                  {SEVERITY_LABELS[s]}
                </option>
              ))}
            </Select>
            <p className="text-body-sm text-on-surface-variant">
              {isAdmin
                ? "Le manager de l'équipe ou l'administration pourra l'ajuster."
                : "Votre manager ou l'administration pourra l'ajuster."}
            </p>
          </Field>
        )}

        {resubmit?.attachment_path && !attachment && (
          <label className="flex items-center gap-xs text-body-sm text-on-surface">
            <input
              type="checkbox"
              checked={keepAttachment}
              onChange={(e) => setKeepAttachment(e.target.checked)}
            />
            Garder la pièce jointe actuelle : {resubmit.attachment_name ?? "document PDF"}
          </label>
        )}

        <Field
          label={
            resubmit?.attachment_path
              ? "Remplacer par un autre PDF (optionnel, 20 Mo max)"
              : "Document PDF (optionnel, 20 Mo max)"
          }
          error={errors.attachment}
        >
          <input
            type="file"
            accept="application/pdf,.pdf"
            className="block w-full text-body-sm"
            onChange={(e) => {
              const f = e.target.files?.[0] ?? null;
              const fail = (message: string) => {
                setErrors((prev) => ({ ...prev, attachment: message }));
                e.target.value = "";
                setAttachment(null);
              };
              if (f && f.type !== "application/pdf")
                return fail("Seuls les fichiers PDF sont acceptés.");
              if (f && f.size > 20 * 1024 * 1024) return fail("Le fichier dépasse 20 Mo.");
              setErrors((prev) => {
                const { attachment: _a, ...rest } = prev;
                return rest;
              });
              setAttachment(f);
            }}
          />
        </Field>

        <FormActions
          pending={submit.isPending}
          submitLabel={resubmit ? "RENVOYER" : "ENVOYER"}
          onCancel={onClose}
        />
      </form>
    </Modal>
  );
}
