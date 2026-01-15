<div align="center">
  <img src="https://www.eii.ulpgc.es/sites/default/files/eii-acron-mod.png"
      alt="Logo ULPGC"
      width="400"
      style="margin-bottom: 10px;"
   >
</div>

<h1 align="center">Práctica Obligatoria 2 - Ingesta y procesamiento de datos en AWS</h1>

<div align="center" style="font-family: 'Segoe UI', sans-serif; line-height: 1.6; margin-top: 30px;">
  <h2 style="font-size: 28px; margin-bottom: 10px;">
    Grado en Ingeniería Informática
  </h2>
  <h3 style="font-size: 24px; margin-bottom: 10px;">
    Computación en la Nube
  </h3>
</div>

**Autor:** Ayman Asbai Ghoudan  

**Curso académico:** 2025/26  

---

### Preparación del Entorno con `uv`

Los comandos que se observan a continuación crearán el proyecto correspondiente, instalarán las dependencias necesarias para su ejecución y activarán el entorno virtual.

**Crear proyecto e instalar dependencias:**

```bash
# 1. inicializa el proyecto
uv init

# 2. Instalar boto3 (la librería de AWS para Python)
uv add boto3
uv add loguru

# 3. Crear el entorno virtual (si no se creó automáticamente con init)
uv venv
```

**Activar el entorno virtual:**
En este caso, se decidió utilizar la versión de *Linux*, pero también se adjuntan los procedimientos para las posibles alternativas.

- **Linux / macOS:**

  ```bash
  source .venv/bin/activate
  ```

- **Windows (PowerShell):**

  ```powershell
  .venv\Scripts\activate
  ```

- **Windows (CMD):**

  ```cmd
  .venv\Scripts\activate.bat
  ```

---
