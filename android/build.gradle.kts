allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

plugins{ //firebase json plugin code
    id("com.google.gms.google-services") version "4.4.2" apply false
}

//buildscript {
  //  dependencies {
    //    classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.8.0")
    //}
//}