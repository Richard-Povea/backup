function Get-LeftBackups{
    param (
        [string] $listName
    )
    $camlNoTerminados = "@
    <View>
        <Query>
            <Where>
                <Or>
                    <Eq>
                        <FieldRef Name='Backup' />
                        <Value Type='Text'>No iniciado</Value>
                    </Eq>
                    <Eq>
                        <FieldRef Name='Backup' />
                        <Value Type='Text'>En proceso</Value>
                    </Eq>
                </Or>
            </Where>
        </Query>
    </View>"
    return Get-PnPListItem -List $listName -Query $camlNoTerminados
}

