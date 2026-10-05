#![deny(clippy::unwrap_used, clippy::expect_used)]

fn main() -> Result<(), std::io::Error> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    runtime.block_on(serve())
}

async fn serve() -> Result<(), std::io::Error> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000").await?;
    axum::serve(listener, helpmemove_api::app()).await
}
