// Input layout: <ini file bytes> [ '\0' <arguments: k=v;k=v> [ '\0' <overwrites: sec.key=v;...> ] ]
#include <dsn/utility/configuration.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    std::string parts[3];
    size_t idx = 0;
    for (size_t i = 0; i < size; ++i)
    {
        if (data[i] == '\0' && idx < 2)
            ++idx;
        else
            parts[idx].push_back((char)data[i]);
    }

    const char *tmpdir = getenv("TMPDIR");
    std::string path = std::string(tmpdir && *tmpdir ? tmpdir : "/tmp") + "/rdsn_cfg_XXXXXX";
    int fd = mkstemp(&path[0]);
    if (fd < 0)
        return 0;
    size_t off = 0;
    while (off < parts[0].size())
    {
        ssize_t n = write(fd, parts[0].data() + off, parts[0].size() - off);
        if (n <= 0)
            break;
        off += (size_t)n;
    }
    close(fd);

    {
        dsn::configuration cfg;
        bool ok = cfg.load(path.c_str(),
                           idx >= 1 ? parts[1].c_str() : nullptr,
                           idx >= 2 ? parts[2].c_str() : nullptr);
        if (ok)
        {
            std::vector<std::string> sections;
            cfg.get_all_sections(sections);
            for (auto &s : sections)
            {
                // get_string_value[_list] leave their out-pointer uninitialised for an empty
                // section/key (which a config can hold through "sec.=v" overwrites). Callers pass
                // literal names, so only query what a caller could ask for.
                if (s.empty())
                    continue;
                std::vector<const char *> keys;
                cfg.get_all_keys(s.c_str(), keys);
                for (auto k : keys)
                {
                    if (k[0] == '\0')
                        continue;
                    cfg.get_string_value(s.c_str(), k, "", "");
                    cfg.get_value<int64_t>(s.c_str(), k, 0, "");
                    cfg.get_value<double>(s.c_str(), k, 0.0, "");
                    cfg.get_value<bool>(s.c_str(), k, false, "");
                    cfg.get_string_value_list(s.c_str(), k, ',', "");
                }
            }
        }
    }
    unlink(path.c_str());
    return 0;
}
