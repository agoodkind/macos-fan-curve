import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            disableSandbox: false,
            includeGenerateScheme: true
        )
    )
)
