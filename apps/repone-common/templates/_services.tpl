{{- define "repone-common.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "repone-common.name" . }}
  namespace: {{ include "repone-common.namespace" . }}
  labels:
    {{- include "repone-common.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "repone-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: {{ include "repone-common.name" . }}
      port: {{ .Values.port }}
      targetPort: {{ .Values.port }}
{{- end }}