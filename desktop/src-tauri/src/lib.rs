mod auth;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(auth::AuthRuntime::default())
        .plugin(tauri_plugin_http::init())
        .plugin(
            tauri_plugin_opener::Builder::new()
                .open_js_links_on_click(false)
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            auth::cancel_login,
            auth::get_current_user,
            auth::login,
            auth::logout
        ])
        .run(tauri::generate_context!())
        .expect("error al ejecutar MusicFlow Desktop");
}
