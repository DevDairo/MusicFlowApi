const boundaries = [
  "Cliente instalado en Windows",
  "API publicada por separado",
  "Worker y PostgreSQL privados",
] as const;

export function App() {
  return (
    <main className="app-shell">
      <section className="hero" aria-labelledby="app-title">
        <div className="brand-mark" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <p className="eyebrow">MusicFlow Desktop</p>
        <h1 id="app-title">Tu audio, procesado con una arquitectura clara.</h1>
        <p className="summary">
          Esta primera compilacion valida el cliente nativo. La conexion con la
          API se incorporara solamente despues de comprobar el instalador.
        </p>

        <div className="status-card" role="status">
          <span className="status-dot" aria-hidden="true" />
          <div>
            <strong>Puerta A preparada</strong>
            <p>Esqueleto local, sin permisos del sistema ni secretos.</p>
          </div>
        </div>

        <ul className="boundaries" aria-label="Limites de despliegue">
          {boundaries.map((boundary) => (
            <li key={boundary}>{boundary}</li>
          ))}
        </ul>
      </section>

      <footer>
        <span>Incremento tecnico 2</span>
        <span>Tauri + React + TypeScript</span>
      </footer>
    </main>
  );
}
