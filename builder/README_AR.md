# XsGPS APK/XAPK Builder — Railway

Docker-backed builder for **owned or explicitly authorized Android Debug APK/XAPK**. The source is stored in four SHA-256-verified Brotli/base64 parts (source.part1 through source.part4); Dockerfile expands them into server.py, requirements.txt and static/index.html. A readable source ZIP is also supplied separately.

- Upload APK or XAPK (450 MB configured; actual limits depend on available Railway resources and HTTP upload duration).
- Only modifies debuggable APKs. Adds the existing Android XsGPS AAR as a DEX, starts the authorized app overlay via Application startup, and signs the output with a fresh test key.
- XAPK repacking preserves split APK and OBB files and uses the same test key to re-sign every split. Use an XAPK installer where required.
- Standard Android Mock Location. No integrity bypass or concealment.
- Outputs expire after roughly an hour. Run one worker per Railway replica and don't assume persistence across restarts.
- Set Railway BUILDER_TOKEN and enter the token in the website before uploading private apps.
- Service Dockerfile: builder/Dockerfile. Service config: builder/railway.toml. Keep the repository root build context; Docker needs android/xsgpslib.
- API: POST /api/build, GET /api/status/{job_id}, GET /api/download/{job_id}?ticket=..., GET /api/health.
