{{- define "repone-common.pvc" -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "repone-common.name" . }}-pvc
  namespace: {{ include "repone-common.namespace" . }}
  labels:
    {{- include "repone-common.labels" . | nindent 4 }}
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: {{ .Values.persistence.size | default "1Gi" }}
{{- end }}
