{{- define "repone-common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "repone-common.name" . }}
  namespace: {{ include "repone-common.namespace" . }}
  labels:
    {{- include "repone-common.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  strategy:
    type: {{ .Values.strategy }}
  selector:
    matchLabels:
      {{- include "repone-common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "repone-common.selectorLabels" . | nindent 8 }}
    spec:
      {{- if .Values.persistence.enabled }}
      securityContext:
        fsGroup: 1000
      {{- end }}
      containers:
        - name: {{ include "repone-common.name" . }}
          image: "{{ .Values.image.repository }}:{{ required "image.tag es obligatorio" .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: {{ include "repone-common.name" . }}
              containerPort: {{ .Values.port }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.path }}
              port: {{ .Values.port }}
            initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.path }}
              port: {{ .Values.port }}
            initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
            timeoutSeconds: 5
          {{- if or .Values.env .Values.secretName }}
          env:
            {{- if .Values.port }}
            - name: PORT
              value: {{ .Values.port | quote }}
            {{- end }}
            {{- if .Values.secretName }}
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.secretName }}
                  key: JWT_SECRET
            {{- end }}
            {{- with .Values.env }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
          {{- if .Values.persistence.enabled }}
          volumeMounts:
            - name: data
              mountPath: {{ .Values.persistence.mountPath }}
          {{- end }}
      {{- if .Values.persistence.enabled }}
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: {{ include "repone-common.name" . }}-pvc
      {{- end }}
{{- end }}