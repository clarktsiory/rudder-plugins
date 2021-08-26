# this file is an include which define general variable.
# It also parse all the variable in main-build.conf 
# and define variables accordingly


MAIN_BUILD          = $(shell  [ -f main-build.conf ] && echo '.' || echo '..')/main-build.conf
RUDDER_VERSION       = $(shell sed -ne '/^rudder-version=/s/rudder-version=//p' $(MAIN_BUILD))
RUDDER_VERSION_NEXT  = $(shell sed -ne '/^rudder-version-next=/s/rudder-version-next=//p' $(MAIN_BUILD))
COMMON_VERSION  = $(shell sed -ne '/^common-version=/s/common-version=//p' $(MAIN_BUILD))
PRIVATE_VERSION  = $(shell sed -ne '/^private-version=/s/private-version=//p' $(MAIN_BUILD))


ifneq (,$(wildcard ./build.conf))
PLUGIN_VERSION   = $(shell sed -ne '/^plugin-version=/s/plugin-version=//p' build.conf)
NAME            = $(shell sed -ne '/^plugin-name=/s/plugin-name=//p' build.conf)
FULL_NAME       = rudder-plugin-$(NAME)
endif

LIB_PRIVATE_NAME = plugins-common-private
LIB_PUBLIC_NAME = plugins-parent
LIB_PRIVATE_VERSION = ${PRIVATE_VERSION}
LIB_PUBLIC_VERSION = ${COMMON_VERSION}


# if you want to add maven command line parameter, add them with MVN_PARAMS
MVN_CMD = mvn $(MVN_PARAMS) --batch-mode 

generate-pom: PLUGIN_POM_VERSION = $(RUDDER_VERSION)-${PLUGIN_VERSION}
generate-pom: RUDDER_BUILD_VERSION = $(RUDDER_VERSION)
generate-pom: RUDDER_POM_VERSION = $(RUDDER_VERSION)
generate-pom: build-pom

generate-pom-nightly: PLUGIN_POM_VERSION = $(RUDDER_VERSION)-${PLUGIN_VERSION}-SNAPSHOT
generate-pom-nightly: RUDDER_BUILD_VERSION = $(RUDDER_VERSION)
generate-pom-nightly: RUDDER_POM_VERSION = $(RUDDER_VERSION)
generate-pom-nightly: build-pom

generate-pom-next: PLUGIN_POM_VERSION = $(RUDDER_VERSION_NEXT)-${PLUGIN_VERSION}-SNAPSHOT
generate-pom-next: RUDDER_BUILD_VERSION = $(RUDDER_VERSION_NEXT)-SNAPSHOT
generate-pom-next: RUDDER_POM_VERSION = $(RUDDER_VERSION)
generate-pom-next: build-pom

build-pom:
	cp pom-template.xml pom.xml
	sed -i -e "s/\$${plugin-version}/${PLUGIN_POM_VERSION}/" pom.xml
	sed -i -e "s/\$${parent-version}/${RUDDER_POM_VERSION}-${COMMON_VERSION}/" pom.xml
	sed -i -e "s/\$${private-version}/${RUDDER_POM_VERSION}-${PRIVATE_VERSION}/" pom.xml
	sed -i -e "s/\$${rudder-version}/$(RUDDER_POM_VERSION)/" pom.xml
	sed -i -e "s/\$${rudder-build-version}/$(RUDDER_BUILD_VERSION)/" pom.xml

