import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import "./styles.css";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("No se encontro el elemento raiz de la aplicacion.");
}

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
