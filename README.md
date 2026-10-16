# retail-inventory-gitops

Repositorio GitOps de **Reponé**. Contiene el chart de Helm de los microservicios, las `Application` de ArgoCD que los sincronizan con el cluster k3s, la configuración de entrada (Gateway API + Traefik) y el stack de monitoreo (Prometheus + Grafana). El cluster refleja lo que hay en la rama `master`.

## Repositorios relacionados

| Repo | Contenido |
|------|-----------|
| `retail-inventory-app` | Código de los servicios, Dockerfiles y workflows de CI (GitHub Actions) |
| `retail-inventory-terraform` | Infraestructura en AWS (repositorios ECR) |
| `retail-inventory-gitops` | Este repo: estado deseado del cluster |

## Estructura

```
.
├── apps/
│   ├── repone-chart/          # chart que ArgoCD despliega (uno solo para los 4 servicios)
│   │   ├── templates/         # deployment, service y pvc
│   │   ├── values.yaml        # valores por defecto
│   │   └── values/            # un archivo por servicio (nombre, puerto, imagen, tag)
│   ├── repone-common/         # library chart (en migración, ver más abajo)
│   ├── <servicio>/            # charts que consumen repone-common (todavía sin uso)
│   └── monitoring-chart/
│       └── values.yaml        # valores de kube-prometheus-stack (no es un chart, solo values)
├── argocd/
│   ├── app-of-apps.yaml       # Application raíz: crea las demás
│   └── apps/                  # una Application por servicio + monitoring
└── gateway-api/               # entrada al cluster
    ├── traefik-config.yaml    # habilita el provider de Gateway API en Traefik
    ├── gateway.yaml           # listener HTTP compartido (acepta rutas de cualquier namespace)
    ├── httproute.yaml         # repone.landriel.site → frontend
    └── httproute-grafana.yaml # grafana.repone.landriel.site → Grafana
```

Un mismo chart (`repone-chart`) sirve a los 4 servicios. Cada `Application` de ArgoCD lo usa con su propio archivo de valores:

```yaml
helm:
  valueFiles:
    - values.yaml
    - values/auth-service.yaml
```

No hay separación por entornos: hay un único cluster y un único entorno.

## Flujo de despliegue

1. Un push al repo de la app (cambios en `services/<servicio>/`) dispara el workflow del servicio.
2. El workflow se autentica en AWS con OIDC, construye la imagen y la sube a ECR con el SHA del commit como tag.
3. El job `update-gitops` actualiza `image.tag` en `apps/repone-chart/values/<servicio>.yaml` y commitea en este repo.
4. ArgoCD detecta el cambio y sincroniza el cluster.

Los 4 workflows commitean en este repo, así que el job `update-gitops` usa `concurrency: gitops-push` para que corran de a uno y no choquen en el push.

## Cómo se arma el cluster

Requisitos: k3s corriendo, ArgoCD instalado en el namespace `argocd` y el namespace `repone` creado.

1. Habilitar Gateway API en Traefik (el que trae k3s). Traefik se reinicia solo y crea la `GatewayClass` `traefik`:

   ```bash
   kubectl apply -f gateway-api/traefik-config.yaml
   kubectl get gatewayclass
   ```

2. Crear los secrets del namespace `repone` (ver [Secrets](#secrets)).

3. Aplicar la app raíz, que crea las `Application` de los 4 servicios:

   ```bash
   kubectl apply -f argocd/app-of-apps.yaml
   ```

4. Aplicar el Gateway y las rutas:

   ```bash
   kubectl apply -f gateway-api/gateway.yaml
   kubectl apply -f gateway-api/httproute.yaml
   kubectl apply -f gateway-api/httproute-grafana.yaml   # después de que ArgoCD cree el namespace monitoring
   ```

5. Verificar:

   ```bash
   kubectl get applications -n argocd      # Synced / Healthy
   kubectl get pods,svc -n repone          # 4 servicios corriendo
   kubectl get httproute -A                # ResolvedRefs=True (repone y monitoring)
   kubectl get pods -n monitoring          # Prometheus, Grafana, operator, exporters
   ```

La `Application` `monitoring` la crea la app raíz junto con las de los servicios (ver [Monitoreo](#monitoreo)).

## Cómo se accede

Todo entra por **Traefik** (el que trae k3s) usando **Gateway API** en lugar de `Ingress`. Hay dos hostnames sobre HTTP:

| Hostname | Namespace de la ruta | Destino |
|---|---|---|
| `repone.landriel.site` | `repone` | Service `frontend` (puerto 80) |
| `grafana.repone.landriel.site` | `monitoring` | Service `monitoring-grafana` (puerto 80) |

- **DNS:** registros `A` `repone` y `grafana.repone` → IP del nodo, en modo *DNS only*.
- **Traefik:** `traefik-config.yaml` es un `HelmChartConfig` que activa `providers.kubernetesGateway`. Con eso Traefik crea la `GatewayClass` `traefik`.
- **Gateway:** un único `repone-gateway` (namespace `repone`) escucha en el puerto `8000`, que es el entrypoint interno `web` de Traefik (el Service lo expone como `80`). Tiene `allowedRoutes.namespaces.from: All`, así que acepta `HTTPRoute` de otros namespaces, como `monitoring`.
- **Rutas:** cada `HTTPRoute` vive en el namespace de su backend y se engancha al Gateway con `parentRefs` (la de Grafana indica `namespace: repone`). Como la ruta y el Service están en el mismo namespace, no hace falta `ReferenceGrant`.
- **Frontend:** su nginx proxea `/api/auth`, `/api/catalog` y `/api/orders` a los backends por DNS interno del cluster, así que los backends no se exponen y no hay CORS.

## Monitoreo

`argocd/apps/monitoring.yaml` despliega **kube-prometheus-stack** (Prometheus, Grafana, operator, node-exporter, kube-state-metrics) en el namespace `monitoring`. Usa dos fuentes (multi-source): el chart oficial de `prometheus-community` en la versión `92.3.1`, y este repo como `ref: values` para leer `apps/monitoring-chart/values.yaml`. El namespace se crea con `CreateNamespace=true` y se usa `ServerSideApply=true` por el tamaño de los CRDs.

Ajustes en `values.yaml`, pensados para un nodo chico:

- **Alertmanager** desactivado (no se usa todavía, ahorra RAM).
- **etcd, scheduler, controller-manager y kube-proxy** desactivados: en k3s corren embebidos en un solo proceso y generarían targets *down* permanentes.
- **Prometheus:** retención de 3 días, `requests` 100m CPU / 512Mi y `limit` de 1Gi de memoria.
- **Grafana:** `requests` 50m / 128Mi y `limit` 384Mi. `GF_PLUGINS_PREINSTALL_DISABLED` evita bajar plugins de grafana.com al arrancar, y SQLite corre en modo WAL (menos locks).

**Acceso a Grafana:** `http://grafana.repone.landriel.site`. El usuario es `admin` y la contraseña la genera el chart en el secret `monitoring-grafana`:

```bash
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

Los dashboards de Kubernetes (nodos, pods, namespaces) vienen incluidos en el chart. Las métricas propias de los servicios (`/metrics`) todavía **no** se scrapean: falta definir los `ServiceMonitor` en el chart de la app.

## Secrets

Los secrets no se commitean. Hoy hay dos y se crean a mano en el namespace `repone`:

| Secret | Para qué | Clave |
|---|---|---|
| `auth-service-secret` | Firma y validación del JWT (lo usan los 3 backends) | `JWT_SECRET` |
| `ecr-pull-secret` | Bajar imágenes del ECR privado (`imagePullSecrets`) | `.dockerconfigjson` |

```bash
kubectl create secret generic auth-service-secret \
  --from-literal=JWT_SECRET=<valor> -n repone
```

El token de ECR **vence a las 12 horas**, y por ahora se renueva a mano:

```bash
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=<cuenta>.dkr.ecr.us-east-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-2)" \
  -n repone --dry-run=client -o yaml | kubectl apply -f -
```

Si un pod queda en `ImagePullBackOff`, casi siempre es este secret vencido. Después de renovarlo: `kubectl rollout restart deployment -n repone`.

## Migración a library chart (en curso)

`apps/repone-common` es un library chart con los templates reutilizables (`deployment`, `service`, `pvc`), y `apps/<servicio>/` son charts que lo consumen. **ArgoCD todavía no los usa**: las `Application` apuntan a `apps/repone-chart`. Cuando la migración termine, las `Application` pasarán a apuntar a cada `apps/<servicio>`.

## Convenciones

- Las imágenes se referencian por tag inmutable (SHA del commit), nunca `latest`. Los tags de ECR también son inmutables: no se puede volver a subir un SHA ya publicado, así que un build se repite solo con un commit nuevo o con *Re-run failed jobs*.
- La rama de este repo es `master` (el `targetRevision` de todas las `Application`). El repo de la app usa `main`.
- Un servicio por archivo en `apps/repone-chart/values/` y una `Application` por servicio en `argocd/apps/`.
- Los recursos de la app se despliegan en el namespace `repone` y los de monitoreo en `monitoring`.
- Las rutas de entrada se definen con `HTTPRoute` (Gateway API), no con `Ingress`, y viven en el namespace de su backend.
